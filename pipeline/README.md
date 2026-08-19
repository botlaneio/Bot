# Ingestion pipeline

Polls public ATS job boards for a watchlist of companies, stores each posting's
lifecycle, and turns that into the signals the outbound service sells: a role
open 60+ days, a role quietly reposted, a role posted and then withdrawn with no
hire.

Decided 2026-08-18 (`docs/decisions.md`). The reasoning is in
`docs/ingestion-recommendation.md`; this file is how it works.

## The one thing that matters

**"Open 60+ days" is free. Everything else is only true if we watched.**

The ATS platforms publish their own posting dates, so age is computable the first
time a board is read (verified 2026-08-17, `scripts/ats_probe*.py`). Reposts and
withdrawals are not: they are the difference between yesterday's board and
today's. There is no backfill, no vendor to buy it from, and no way to catch up.
A day the poll does not run is a day of signal that does not exist.

That is why the schedule lives in GitHub Actions rather than on this machine.

## Shape

```
pipeline/ats.py       fetch + normalise the three ATS APIs. Decides nothing.
pipeline/store.py     two RPC calls to Supabase. Holds no logic.
pipeline/poll.py      the daily job.
pipeline/discover.py  find a company's boards and put them on the watchlist.
pipeline/replay.sql   apply captured payloads by hand.
pipeline/tests/       lifecycle test for the ingest function.
```

The interesting half is in the database:

```
supabase/migrations/20260818152233_pipeline_ingestion_core.sql   schema
supabase/migrations/20260818152310_pipeline_ingest_function.sql  ingest_ats_board
supabase/migrations/20260818153940_pipeline_close_by_run_id.sql  the fix below
supabase/migrations/20260818154520_pipeline_active_boards.sql    the poll list
```

`public.ingest_ats_board(payload jsonb)` takes one board's whole fetch and does
the entire diff in one transaction: upsert postings, emit lifecycle events, close
what vanished. The Python is deliberately dumb — it fetches, renames fields, and
reports whether the fetch worked. Every claim that could end up in a customer's
email is decided in one place.

Tables live in the `pipeline` schema, which PostgREST does not expose. Writes
arrive through the one function in `public`, granted to `service_role` alone.

## Running it

```bash
python -m pipeline.poll                      # every active board
python -m pipeline.poll --limit 25           # the least recently seen
python -m pipeline.poll --board ashby:linear
python -m pipeline.poll --dry-run            # fetch, report, write nothing

python -m pipeline.discover --slugs-file pipeline/watchlist_seed.txt --max-open-roles 120
python -m pipeline.discover --from-sample sized_final.json
```

Needs `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` — repository secrets in CI,
`Bot/.env.local.txt` locally (gitignored). stdlib only: no manifest, no install
step, nothing to keep up to date.

Scheduled daily at 13:17 UTC by `.github/workflows/ingest.yml`.

## Reading the results

```sql
select * from pipeline.stale_openings limit 40;   -- roles open 60+ days
select * from pipeline.repost_signals;            -- vanished, then came back
select * from pipeline.board_health;              -- boards going quiet
select * from pipeline.open_postings where company = 'pylon';
```

`open_postings.days_open_is_observed` is the honesty flag. True means the ATS
published no date and the age is only "since we started watching" — those must
not be quoted in outbound, where the whole pitch is that the number is
indisputable.

## Two failure modes it is built around

**A failed fetch must never read as a withdrawal.** An HTTP error, a timeout, a
renamed board — all produce "the posting is not in today's response", which is
also what a genuine withdrawal produces. Nothing is closed unless the fetch
demonstrably succeeded, and a board that returns an empty list while we hold open
postings for it is recorded as `empty_unexpected` and changes nothing. Both cases
are visible in `pipeline.poll_runs` and `pipeline.board_health`.

**A board that quietly stops answering loses signal silently.** Nothing errors;
the postings simply stop updating. `board_health.last_ok_at` versus
`last_polled_at` is where that shows up.

## A bug worth remembering

The first version decided "this run did not see that posting" with
`last_seen_at < now()`. `now()` is *transaction* time, so two polls of one board
inside a single transaction shared an instant and the second closed nothing. In
production each daily poll is its own transaction, so this would never have
appeared in normal operation — it would have appeared the first time a backfill
or a retry replayed two fetches together, as silently missing withdrawals rather
than an error.

`pipeline/tests/lifecycle_test.sql` caught it on the day it was written, before a
single real posting was ingested. Closure is now decided by run identity
(`postings.last_seen_run_id`), which has no dependence on the clock at all.

Run it after any change to the ingest function:

```sql
select pipeline._lifecycle_test();
```

It creates its own company, asserts six lifecycle steps, deletes it, and returns
`{"passed": true, ...}`. Safe against the live project.

## Not built yet

- **Title drift** ("backend engineer (some infra)" reposted over months) needs
  semantic matching across postings where both the ID and the wording changed.
  Sequenced last on purpose: a similarity threshold means false positives, and a
  false positive here is a wrong sentence in a customer's email.
- **Scoring, enrichment, drafting, reporting.** Enrichment is blocked on a paid
  data source — Apollo's free plan has no API at all (`decisions.md`
  2026-08-17). Nothing sends before the CAN-SPAM decision (R2).
