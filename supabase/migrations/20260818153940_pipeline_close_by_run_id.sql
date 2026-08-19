-- Close postings by run identity, not by clock.
--
-- Caught by pipeline/tests/lifecycle_test.sql on the day the pipeline was
-- built, before any real posting was ingested.
--
-- The first cut decided "this run did not see that posting" with
-- `last_seen_at < now()`. now() is TRANSACTION time, so two polls of the same
-- board inside one transaction share an instant and the second one closes
-- nothing. In production each daily poll is its own transaction, so the bug
-- would not have shown up in normal operation — it would have shown up the
-- first time a backfill, a retry, or a test replayed two fetches together, and
-- the symptom would have been silently missing withdrawals rather than an
-- error.
--
-- Run identity has no such ambiguity: a posting seen by this run carries this
-- run's id, and everything else on the board did not appear in this fetch.
-- It also makes the question auditable after the fact — every posting now
-- records which poll last saw it.

alter table pipeline.postings
    add column last_seen_run_id uuid references pipeline.poll_runs (id) on delete set null;

comment on column pipeline.postings.last_seen_run_id is
    'The poll run that last observed this posting present. Closure is decided by comparing this to the current run, never by comparing timestamps — see migration 20260818153940.';

create index postings_last_seen_run_id_idx on pipeline.postings (last_seen_run_id);

create or replace function public.ingest_ats_board(payload jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $fn$
declare
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

    delete from pg_temp._incoming a
     using pg_temp._incoming b
     where a.posting_id = b.posting_id and a.ctid > b.ctid;

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

    insert into pipeline.posting_snapshots
                (posting_id, run_id, observed_at, present, title, location,
                 employment_type, content_hash, raw)
    select p.id, v_run, v_now, true, i.title, i.location, i.employment_type,
           i.content_hash, i.raw
      from pipeline.postings p
      join pg_temp._incoming i on i.posting_id = p.posting_id
     where p.board_id = v_board
       and (p.content_hash is distinct from i.content_hash or p.state = 'closed');

    update pipeline.postings p
       set title              = i.title,
           location           = i.location,
           employment_type    = i.employment_type,
           url                = coalesce(i.url, p.url),
           first_published_at = coalesce(i.first_published_at, p.first_published_at),
           content_hash       = i.content_hash,
           raw                = coalesce(i.raw, p.raw),
           last_seen_at       = v_now,
           last_seen_run_id   = v_run,
           state              = 'open',
           closed_at          = null,
           reopen_count       = p.reopen_count + case when p.state = 'closed' then 1 else 0 end,
           last_reopened_at   = case when p.state = 'closed' then v_now else p.last_reopened_at end
      from pg_temp._incoming i
     where p.board_id = v_board and p.posting_id = i.posting_id;

    with fresh as (
        insert into pipeline.postings
                    (organization_id, board_id, source, board_token, posting_id,
                     title, location, employment_type, url, first_published_at,
                     first_seen_at, last_seen_at, last_seen_run_id, content_hash, raw)
        select v_org, v_board, v_source, v_token, i.posting_id, i.title,
               i.location, i.employment_type, i.url, i.first_published_at,
               v_now, v_now, v_run, i.content_hash, i.raw
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

    -- The fix: not "older than this instant" but "not touched by this run".
    with gone as (
        update pipeline.postings p
           set state = 'closed', closed_at = v_now
         where p.board_id = v_board
           and p.state = 'open'
           and p.last_seen_run_id is distinct from v_run
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

revoke all on function public.ingest_ats_board(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_ats_board(jsonb) to service_role;
