-- BotLane ingestion pipeline — the ingest entry point.
--
-- ONE function, called once per board per poll, taking the whole fetch as a
-- single jsonb payload and doing the entire diff inside one transaction.
--
-- Why the diff lives in the database rather than in the poller:
--
--   * ATOMICITY. A poll either records the board completely or not at all.
--     A poller that crashes between "mark these seen" and "close the rest"
--     would fabricate withdrawals — the most expensive kind of wrong, because
--     a withdrawal is a claim we put in an email.
--   * ONE PAYLOAD, THREE TRANSPORTS. A single jsonb argument is callable over
--     psql, over PostgREST (/rest/v1/rpc/ingest_ats_board), and through the
--     Supabase MCP connector, with no SQL string-building and no escaping
--     matrix in the client. The scheduler can therefore change without the
--     ingest logic changing.
--   * THE LOGIC IS INSPECTABLE. Signal rules are the product; they belong
--     somewhere they can be read and tested directly, not spread across a
--     Python process that only runs on a cron box.
--
-- The poller stays deliberately dumb: fetch, normalise, hand over. It makes no
-- lifecycle decisions at all.
--
-- Payload shape:
--   {
--     "source":            "greenhouse" | "ashby" | "lever",
--     "board_token":       "acme",                -- discovered, never derived
--     "organization_slug": "acme",                -- defaults to board_token
--     "organization_name": "Acme Inc",            -- optional
--     "board_url":         "https://...",         -- optional
--     "fetch_status":      "ok" | "http_error" | "network_error" | "parse_error",
--     "http_status":       200,                   -- optional
--     "error":             "timeout after 20s",   -- optional
--     "started_at":        "2026-08-18T15:00:00Z",-- optional
--     "postings": [
--       { "posting_id": "4012345", "title": "Senior Platform Engineer",
--         "location": "San Francisco, CA", "employment_type": "FullTime",
--         "url": "https://...", "first_published_at": "2026-05-02T00:00:00Z",
--         "raw": { ... } }
--     ]
--   }
--
-- Returns a jsonb summary of what changed, which is what the poller logs.

create or replace function public.ingest_ats_board(payload jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $fn$
declare
    -- now() is transaction time, so every row written by this call shares one
    -- instant. The close step depends on that: "not touched by this run" is
    -- expressed as last_seen_at < v_now.
    v_now        timestamptz := now();
    v_source     text := payload->>'source';
    v_token      text := payload->>'board_token';
    v_org_slug   text := coalesce(nullif(payload->>'organization_slug', ''), payload->>'board_token');
    v_fetch      text := coalesce(payload->>'fetch_status', 'ok');
    v_started    timestamptz := coalesce((payload->>'started_at')::timestamptz, v_now);
    v_org        uuid;
    v_board      uuid;
    v_run        uuid;
    v_status     text;
    v_incoming   integer := 0;
    v_open_before integer := 0;
    v_new        integer := 0;
    v_closed     integer := 0;
    v_reopened   integer := 0;
    v_changed    integer := 0;
begin
    if v_source is null or v_source not in ('greenhouse', 'ashby', 'lever') then
        raise exception 'ingest_ats_board: unknown source %', coalesce(v_source, 'null')
            using errcode = '22023';
    end if;
    if v_token is null or v_token = '' then
        raise exception 'ingest_ats_board: board_token is required'
            using errcode = '22023';
    end if;
    if coalesce(payload->>'fetch_status', 'ok') = 'ok'
       and jsonb_typeof(coalesce(payload->'postings', '[]'::jsonb)) <> 'array' then
        raise exception 'ingest_ats_board: postings must be an array on a successful fetch'
            using errcode = '22023';
    end if;

    -- ---------------------------------------------------------- watchlist
    -- Upsert rather than require pre-registration: discovering a board is how
    -- a company enters the watchlist, and the poller should never fail because
    -- bookkeeping was done in the wrong order.

    insert into pipeline.organizations (slug, name)
         values (v_org_slug, nullif(payload->>'organization_name', ''))
    on conflict (slug) do update
            set name = coalesce(pipeline.organizations.name, excluded.name)
      returning id into v_org;

    insert into pipeline.ats_boards (organization_id, source, board_token, board_url)
         values (v_org, v_source, v_token, nullif(payload->>'board_url', ''))
    on conflict (source, board_token) do update
            set board_url = coalesce(excluded.board_url, pipeline.ats_boards.board_url)
      returning id into v_board;

    select count(*) into v_open_before
      from pipeline.postings
     where board_id = v_board and state = 'open';

    v_incoming := jsonb_array_length(coalesce(payload->'postings', '[]'::jsonb));

    -- ------------------------------------------------------- run classification
    -- Rule 1 of the schema: nothing is closed on a run that did not
    -- demonstrably succeed. A board that returns nothing while we hold open
    -- postings for it is far more likely to have been renamed, moved ATS, or
    -- started 404ing than to have withdrawn every role on the same day — so it
    -- is recorded as empty_unexpected and changes nothing.

    if v_fetch <> 'ok' then
        v_status := v_fetch;
    elsif v_incoming = 0 and v_open_before > 0 then
        v_status := 'empty_unexpected';
    elsif v_incoming = 0 then
        v_status := 'empty';
    else
        v_status := 'ok';
    end if;

    insert into pipeline.poll_runs
                (board_id, source, board_token, started_at, status, http_status, error)
         values (v_board, v_source, v_token, v_started, v_status,
                 (payload->>'http_status')::integer, nullif(payload->>'error', ''))
      returning id into v_run;

    if v_status <> 'ok' then
        update pipeline.ats_boards
           set last_polled_at = v_now,
               consecutive_failures = case
                   when v_status = 'empty' then 0
                   else consecutive_failures + 1 end,
               last_ok_at = case when v_status = 'empty' then v_now else last_ok_at end
         where id = v_board;

        update pipeline.poll_runs
           set finished_at = v_now, postings_seen = v_incoming
         where id = v_run;

        return jsonb_build_object(
            'run_id', v_run, 'board_id', v_board, 'status', v_status,
            'seen', v_incoming, 'new', 0, 'closed', 0, 'reopened', 0, 'changed', 0);
    end if;

    -- ------------------------------------------------------------- incoming
    -- Materialised once: the diff reads it four times and re-parsing the jsonb
    -- each time would be both slower and a chance for the two reads to differ.

    create temporary table _incoming on commit drop as
    select x.posting_id,
           x.title,
           nullif(x.location, '')        as location,
           nullif(x.employment_type, '') as employment_type,
           nullif(x.url, '')             as url,
           x.first_published_at,
           x.raw,
           md5(concat_ws('|', x.title, coalesce(x.location, ''),
                              coalesce(x.employment_type, ''), coalesce(x.url, ''))) as content_hash
      from jsonb_to_recordset(payload->'postings')
        as x(posting_id text, title text, location text, employment_type text,
             url text, first_published_at timestamptz, raw jsonb)
     where x.posting_id is not null and x.posting_id <> ''
       and x.title is not null and x.title <> '';

    -- A board that lists the same posting_id twice would make the update
    -- ambiguous. Keep one row per identity.
    delete from pg_temp._incoming a
     using pg_temp._incoming b
     where a.posting_id = b.posting_id and a.ctid > b.ctid;

    -- ------------------------------------------------------- events, part 1
    -- Field changes and reposts are detected BEFORE the update, while the old
    -- values are still readable. Each event carries both sides in `detail`, so
    -- a claim in an email can always be traced to the two observations that
    -- produced it.

    insert into pipeline.posting_events
                (posting_id, organization_id, run_id, event_type, occurred_at, detail)
    select p.id, p.organization_id, v_run, e.event_type, v_now,
           jsonb_build_object('from', e.old_value, 'to', e.new_value)
      from pipeline.postings p
      join pg_temp._incoming i on i.posting_id = p.posting_id
     cross join lateral (
            values ('title_changed',           p.title,           i.title),
                   ('location_changed',        p.location,        i.location),
                   ('employment_type_changed', p.employment_type, i.employment_type)
          ) as e(event_type, old_value, new_value)
     where p.board_id = v_board
       and e.old_value is distinct from e.new_value;

    -- Counted separately rather than from the statement above: one posting can
    -- emit three events in a single poll, and postings_changed is meant to read
    -- as "how many roles moved", not "how many rows were written".
    select count(*) into v_changed
      from pipeline.postings p
      join pg_temp._incoming i on i.posting_id = p.posting_id
     where p.board_id = v_board
       and p.state = 'open'
       and p.content_hash is distinct from i.content_hash;

    insert into pipeline.posting_events
                (posting_id, organization_id, run_id, event_type, occurred_at, detail)
    select p.id, p.organization_id, v_run, 'reopened', v_now,
           jsonb_build_object('closed_at', p.closed_at,
                              'days_closed', (v_now::date - p.closed_at::date),
                              'reopen_count', p.reopen_count + 1)
      from pipeline.postings p
      join pg_temp._incoming i on i.posting_id = p.posting_id
     where p.board_id = v_board and p.state = 'closed';

    get diagnostics v_reopened = row_count;

    -- Snapshot every posting whose content moved or whose state moved. Not the
    -- untouched ones: see posting_snapshots' comment for why this is
    -- change-only rather than daily.
    insert into pipeline.posting_snapshots
                (posting_id, run_id, observed_at, present, title, location,
                 employment_type, content_hash, raw)
    select p.id, v_run, v_now, true, i.title, i.location, i.employment_type,
           i.content_hash, i.raw
      from pipeline.postings p
      join pg_temp._incoming i on i.posting_id = p.posting_id
     where p.board_id = v_board
       and (p.content_hash is distinct from i.content_hash or p.state = 'closed');

    -- ------------------------------------------------------------- update
    update pipeline.postings p
       set title              = i.title,
           location           = i.location,
           employment_type    = i.employment_type,
           url                = coalesce(i.url, p.url),
           -- The provider's date is authoritative but must never be erased by
           -- a later fetch that happens to omit it.
           first_published_at = coalesce(i.first_published_at, p.first_published_at),
           content_hash       = i.content_hash,
           raw                = coalesce(i.raw, p.raw),
           last_seen_at       = v_now,
           state              = 'open',
           closed_at          = null,
           reopen_count       = p.reopen_count + case when p.state = 'closed' then 1 else 0 end,
           last_reopened_at   = case when p.state = 'closed' then v_now else p.last_reopened_at end
      from pg_temp._incoming i
     where p.board_id = v_board and p.posting_id = i.posting_id;

    -- ------------------------------------------------------------- insert
    with fresh as (
        insert into pipeline.postings
                    (organization_id, board_id, source, board_token, posting_id,
                     title, location, employment_type, url, first_published_at,
                     first_seen_at, last_seen_at, content_hash, raw)
        select v_org, v_board, v_source, v_token, i.posting_id, i.title,
               i.location, i.employment_type, i.url, i.first_published_at,
               v_now, v_now, i.content_hash, i.raw
          from pg_temp._incoming i
         where not exists (select 1 from pipeline.postings p
                            where p.board_id = v_board and p.posting_id = i.posting_id)
        returning id, organization_id, title, location, employment_type,
                  content_hash, raw, first_published_at
    ), ev as (
        insert into pipeline.posting_events
                    (posting_id, organization_id, run_id, event_type, occurred_at, detail)
        select f.id, f.organization_id, v_run, 'appeared', v_now,
               jsonb_build_object('title', f.title,
                                  'first_published_at', f.first_published_at)
          from fresh f
        returning 1
    )
    insert into pipeline.posting_snapshots
                (posting_id, run_id, observed_at, present, title, location,
                 employment_type, content_hash, raw)
    select f.id, v_run, v_now, true, f.title, f.location, f.employment_type,
           f.content_hash, f.raw
      from fresh f;

    get diagnostics v_new = row_count;

    -- -------------------------------------------------------------- close
    -- Everything on this board still marked open that this run did not touch.
    -- Only reachable when v_status = 'ok', which is the entire point.

    with gone as (
        update pipeline.postings p
           set state = 'closed', closed_at = v_now
         where p.board_id = v_board
           and p.state = 'open'
           and p.last_seen_at < v_now
        returning p.id, p.organization_id, p.title, p.location,
                  p.employment_type, p.content_hash, p.first_published_at,
                  p.first_seen_at
    ), ev as (
        insert into pipeline.posting_events
                    (posting_id, organization_id, run_id, event_type, occurred_at, detail)
        select g.id, g.organization_id, v_run, 'closed', v_now,
               jsonb_build_object(
                   'title', g.title,
                   'first_published_at', g.first_published_at,
                   -- How long it was open when it vanished: the number that
                   -- separates "hired quickly" from "gave up after five months".
                   'days_open_at_close',
                   (v_now::date - coalesce(g.first_published_at, g.first_seen_at)::date))
          from gone g
        returning 1
    )
    insert into pipeline.posting_snapshots
                (posting_id, run_id, observed_at, present, title, location,
                 employment_type, content_hash)
    select g.id, v_run, v_now, false, g.title, g.location, g.employment_type,
           g.content_hash
      from gone g;

    get diagnostics v_closed = row_count;

    -- ------------------------------------------------------------- finish
    update pipeline.ats_boards
       set last_polled_at = v_now, last_ok_at = v_now, consecutive_failures = 0
     where id = v_board;

    update pipeline.poll_runs
       set finished_at = v_now,
           postings_seen = v_incoming,
           postings_new = v_new,
           postings_closed = v_closed,
           postings_reopened = v_reopened,
           postings_changed = v_changed
     where id = v_run;

    drop table if exists pg_temp._incoming;

    return jsonb_build_object(
        'run_id', v_run, 'board_id', v_board, 'organization_id', v_org,
        'status', v_status, 'seen', v_incoming, 'new', v_new,
        'closed', v_closed, 'reopened', v_reopened, 'changed', v_changed);
end;
$fn$;

comment on function public.ingest_ats_board(jsonb) is
    'Ingest one ATS board fetch: upsert postings, emit lifecycle events, close what vanished — atomically. Lives in public only because PostgREST exposes no other schema; execute is granted to service_role alone.';

-- The account-area hardening migration (2026-08-16) removed anon-callable
-- functions from `public` for exactly this reason. This one has to live here to
-- be reachable over /rest/v1/rpc, so the grant is narrowed instead: the
-- operator's service_role key, and nothing else.
revoke all on function public.ingest_ats_board(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_ats_board(jsonb) to service_role;
