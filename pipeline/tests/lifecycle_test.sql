-- Lifecycle test for public.ingest_ats_board.
--
-- The diff IS the product: every claim in an outbound email ("open 71 days",
-- "reposted twice") is an assertion about what this function did. So it is
-- exercised against a synthetic board before real postings are trusted, and
-- especially against the two ways it could lie:
--
--   * closing a posting that did not vanish (a failed fetch read as withdrawal)
--   * missing a repost (same identity gone and back)
--
-- Self-contained and idempotent: creates its own company, asserts, then deletes
-- it. Safe to run against the live project — it touches nothing else.
--
--   Run:  select pipeline._lifecycle_test();
--   or paste this file into the SQL editor. The function drops itself.

create or replace function pipeline._lifecycle_test()
returns jsonb
language plpgsql
as $fn$
declare
    r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb;
    v_open_after_error integer;
    v_open_after_empty integer;
    v_reopen_count integer;
    v_events text;
    failures text[] := '{}';
begin
    delete from pipeline.organizations where slug = 'selftest-acme';

    -- 1. First sight of a board: two postings, both new.
    r1 := public.ingest_ats_board(jsonb_build_object(
        'source', 'greenhouse', 'board_token', 'selftest-acme',
        'organization_name', 'Selftest Acme',
        'postings', jsonb_build_array(
            jsonb_build_object('posting_id', 'A1', 'title', 'Senior Platform Engineer',
                'location', 'San Francisco, CA', 'url', 'https://example.invalid/a1',
                'first_published_at', (now() - interval '80 days')),
            jsonb_build_object('posting_id', 'A2', 'title', 'Site Reliability Engineer',
                'location', 'Remote, US', 'url', 'https://example.invalid/a2',
                'first_published_at', (now() - interval '10 days')))));

    if (r1->>'new')::int <> 2 or (r1->>'status') <> 'ok' then
        failures := failures || format('step 1: expected 2 new / ok, got %s', r1);
    end if;

    -- 2. A2 vanishes. It must close, and only it.
    r2 := public.ingest_ats_board(jsonb_build_object(
        'source', 'greenhouse', 'board_token', 'selftest-acme',
        'postings', jsonb_build_array(
            jsonb_build_object('posting_id', 'A1', 'title', 'Senior Platform Engineer',
                'location', 'San Francisco, CA', 'url', 'https://example.invalid/a1',
                'first_published_at', (now() - interval '80 days')))));

    if (r2->>'closed')::int <> 1 or (r2->>'new')::int <> 0 then
        failures := failures || format('step 2: expected 1 closed / 0 new, got %s', r2);
    end if;

    -- 3. A2 comes back under the same identity — the repost signal.
    r3 := public.ingest_ats_board(jsonb_build_object(
        'source', 'greenhouse', 'board_token', 'selftest-acme',
        'postings', jsonb_build_array(
            jsonb_build_object('posting_id', 'A1', 'title', 'Senior Platform Engineer',
                'location', 'San Francisco, CA', 'url', 'https://example.invalid/a1',
                'first_published_at', (now() - interval '80 days')),
            jsonb_build_object('posting_id', 'A2', 'title', 'Site Reliability Engineer',
                'location', 'Remote, US', 'url', 'https://example.invalid/a2',
                'first_published_at', (now() - interval '10 days')))));

    select reopen_count into v_reopen_count
      from pipeline.postings where posting_id = 'A2' and board_token = 'selftest-acme';

    if (r3->>'reopened')::int <> 1 or v_reopen_count <> 1 or (r3->>'new')::int <> 0 then
        failures := failures || format('step 3: expected 1 reopened, reopen_count 1, 0 new; got %s / count %s',
                                       r3, v_reopen_count);
    end if;

    -- 4. A1 is retitled and becomes a contract role: a change, not a new posting.
    r4 := public.ingest_ats_board(jsonb_build_object(
        'source', 'greenhouse', 'board_token', 'selftest-acme',
        'postings', jsonb_build_array(
            jsonb_build_object('posting_id', 'A1', 'title', 'Staff Platform Engineer',
                'location', 'San Francisco, CA', 'employment_type', 'Contract',
                'url', 'https://example.invalid/a1',
                'first_published_at', (now() - interval '80 days')),
            jsonb_build_object('posting_id', 'A2', 'title', 'Site Reliability Engineer',
                'location', 'Remote, US', 'url', 'https://example.invalid/a2',
                'first_published_at', (now() - interval '10 days')))));

    if (r4->>'changed')::int <> 1 or (r4->>'closed')::int <> 0 then
        failures := failures || format('step 4: expected 1 changed / 0 closed, got %s', r4);
    end if;

    -- 5. THE ONE THAT MATTERS. A failed fetch must close nothing. If this
    --    regresses, the pipeline invents withdrawals and the emails lie.
    r5 := public.ingest_ats_board(jsonb_build_object(
        'source', 'greenhouse', 'board_token', 'selftest-acme',
        'fetch_status', 'http_error', 'http_status', 503,
        'error', 'service unavailable',
        'postings', jsonb_build_array()));

    select count(*) into v_open_after_error
      from pipeline.postings where board_token = 'selftest-acme' and state = 'open';

    if (r5->>'status') <> 'http_error' or (r5->>'closed')::int <> 0 or v_open_after_error <> 2 then
        failures := failures || format('step 5: a failed fetch closed postings — got %s, %s still open',
                                       r5, v_open_after_error);
    end if;

    -- 6. A successful fetch that returns nothing while we hold open postings.
    --    Suspicious (renamed/moved board), not a mass withdrawal.
    r6 := public.ingest_ats_board(jsonb_build_object(
        'source', 'greenhouse', 'board_token', 'selftest-acme',
        'postings', jsonb_build_array()));

    select count(*) into v_open_after_empty
      from pipeline.postings where board_token = 'selftest-acme' and state = 'open';

    if (r6->>'status') <> 'empty_unexpected' or v_open_after_empty <> 2 then
        failures := failures || format('step 6: expected empty_unexpected with 2 still open, got %s / %s',
                                       r6, v_open_after_empty);
    end if;

    -- The signal ledger downstream reads.
    select string_agg(event_type || ':' || count(*), ', ' order by event_type)
      into v_events
      from (select e.event_type, count(*) as count
              from pipeline.posting_events e
              join pipeline.organizations o on o.id = e.organization_id
             where o.slug = 'selftest-acme'
             group by e.event_type) s;

    -- 60+ day rule, on a posting whose provider date is 80 days old.
    if not exists (select 1 from pipeline.stale_openings
                    where company = 'selftest-acme' and days_open between 79 and 81) then
        failures := failures || 'stale_openings did not surface the 80-day posting';
    end if;

    delete from pipeline.organizations where slug = 'selftest-acme';

    return jsonb_build_object(
        'passed', cardinality(failures) = 0,
        'failures', to_jsonb(failures),
        'events_seen', v_events,
        'steps', jsonb_build_array(r1, r2, r3, r4, r5, r6));
end;
$fn$;

-- select pipeline._lifecycle_test();
-- drop function pipeline._lifecycle_test();
