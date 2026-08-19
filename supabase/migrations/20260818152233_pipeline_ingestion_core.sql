-- BotLane ingestion pipeline — core schema.
--
-- Decided 2026-08-18 (docs/decisions.md): Q1 ingestion = poll public ATS JSON
-- endpoints against a curated watchlist; Q2 stack = Python 3.13 + this Postgres.
-- The draft that argued it is docs/ingestion-recommendation.md.
--
-- Four rules this schema enforces:
--
--   1. ABSENCE IS A SIGNAL, SO ABSENCE MUST BE TRUSTWORTHY. "Vanished" and
--      "quietly reposted" are read from a posting NOT being in today's fetch. A
--      failed HTTP call also produces a posting not being in today's fetch. The
--      two must never be confused, so nothing is ever closed on a run that did
--      not demonstrably succeed (see ingest_ats_board, and poll_runs.status).
--   2. BOARD TOKENS ARE DISCOVERED, NEVER DERIVED. Lever slugs are not
--      guessable — eventbrite, kickstarter, quora, mixpanel and box all 404'd
--      on 2026-08-17. Every token is stored per (organization, ATS) as a fact
--      that was observed once, not recomputed from a company name.
--   3. THE PROVIDER'S DATE IS THE PRODUCT. first_published_at holds the ATS's
--      own posting date (Greenhouse first_published / Ashby publishedAt / Lever
--      createdAt). The pitch is "this role has been open 71 days" and the
--      recipient must be unable to dispute it, so our own first_seen_at is
--      recorded separately and never silently substituted.
--   4. COMPANY-LEVEL FROM THE START. Every posting carries organization_id even
--      though nothing aggregates yet, because the title-drift signal is an
--      aggregation across postings and retrofitting that is the expensive kind
--      of migration.
--
-- Status columns are text + CHECK rather than enums, matching the account-area
-- schema and for the same reason: this will change, and adding a value to a
-- CHECK is one line where ALTER TYPE is not.
--
-- The pipeline schema is deliberately NOT exposed by PostgREST. This is
-- operator data with no tenancy dimension — the operator is the only actor —
-- so it has no business having an HTTP surface. Writes arrive through one
-- function in `public` that is granted to service_role alone (next migration).

create schema if not exists pipeline;

grant usage on schema pipeline to service_role;
revoke all on schema pipeline from anon, authenticated;

-- ------------------------------------------------------------ organizations

create table pipeline.organizations (
    id            uuid primary key default gen_random_uuid(),
    -- Our own canonical handle. Usually equals the ATS token, but must not be
    -- assumed to: a company can be on Greenhouse as "acmehq" and Lever as
    -- "acme-inc", and both point at this one row.
    slug          text not null unique,
    name          text,
    domain        text,
    -- The watchlist IS this flag. Turning a company off stops it being polled
    -- without deleting the history already accumulated.
    is_watchlisted boolean not null default true,
    -- Why a company was dropped: "too large", "acquired", "not US", ...
    excluded_reason text,
    notes         text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

comment on table pipeline.organizations is
    'The watchlist. One row per company we watch, independent of how many ATS boards they run.';
comment on column pipeline.organizations.is_watchlisted is
    'False stops polling but preserves accumulated history. Prefer this to deleting.';

-- --------------------------------------------------------------- ats_boards

create table pipeline.ats_boards (
    id            uuid primary key default gen_random_uuid(),
    organization_id uuid not null references pipeline.organizations (id) on delete cascade,
    source        text not null check (source in ('greenhouse', 'ashby', 'lever')),
    -- Discovered by probing, never derived from the company name. See rule 2.
    board_token   text not null,
    board_url     text,
    discovered_at timestamptz not null default now(),
    active        boolean not null default true,
    last_polled_at timestamptz,
    -- Last run that actually returned postings. The gap between this and
    -- last_polled_at is how a silently rotting board announces itself.
    last_ok_at    timestamptz,
    consecutive_failures integer not null default 0,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    unique (source, board_token)
);

create index ats_boards_organization_id_idx on pipeline.ats_boards (organization_id);
create index ats_boards_active_idx on pipeline.ats_boards (active) where active;

comment on column pipeline.ats_boards.board_token is
    'Observed once by probing the ATS, then stored. Never reconstruct it from the company name — Lever slugs in particular are not guessable (decisions.md 2026-08-17).';

-- ---------------------------------------------------------------- poll_runs
-- Written before the diff, updated after it. Exists so that "we did not see
-- that posting today" can be distinguished from "we did not look today".

create table pipeline.poll_runs (
    id            uuid primary key default gen_random_uuid(),
    board_id      uuid references pipeline.ats_boards (id) on delete cascade,
    source        text not null,
    board_token   text not null,
    started_at    timestamptz not null default now(),
    finished_at   timestamptz,
    -- ok               fetch succeeded and returned postings; diff is authoritative
    -- empty            fetch succeeded, board genuinely has no postings
    -- empty_unexpected fetch returned nothing but we hold open postings for this
    --                  board — treated as suspect (moved/renamed board), NOT as
    --                  every role being withdrawn on the same day
    -- http_error / network_error / parse_error — nothing is closed
    status        text not null check (status in
                      ('ok', 'empty', 'empty_unexpected', 'http_error',
                       'network_error', 'parse_error')),
    http_status   integer,
    postings_seen integer not null default 0,
    postings_new  integer not null default 0,
    postings_closed integer not null default 0,
    postings_reopened integer not null default 0,
    postings_changed integer not null default 0,
    error         text
);

create index poll_runs_board_id_started_at_idx on pipeline.poll_runs (board_id, started_at desc);
create index poll_runs_status_idx on pipeline.poll_runs (status) where status <> 'ok';

comment on table pipeline.poll_runs is
    'One row per board per poll attempt. The audit trail that makes absence readable as a signal rather than as an outage.';

-- ----------------------------------------------------------------- postings
-- Natural key (source, board_token, posting_id) — the identity the whole
-- lifecycle hangs off. A posting row is durable: it is never deleted when the
-- role disappears, it is marked closed, because "appeared, vanished, came back"
-- is precisely the signal we sell.

create table pipeline.postings (
    id            uuid primary key default gen_random_uuid(),
    organization_id uuid not null references pipeline.organizations (id) on delete cascade,
    board_id      uuid not null references pipeline.ats_boards (id) on delete cascade,
    source        text not null,
    board_token   text not null,
    posting_id    text not null,
    title         text not null,
    location      text,
    -- Ashby employmentType, Lever categories.commitment. Greenhouse's list
    -- endpoint does not carry it, so null means "not published by this ATS",
    -- not "full time".
    employment_type text,
    url           text,
    -- The ATS's own date. Null only where the provider omits it.
    first_published_at timestamptz,
    -- Ours. Fallback for age when the provider gives nothing, and the only
    -- honest figure for postings that predate our watching.
    first_seen_at timestamptz not null default now(),
    last_seen_at  timestamptz not null default now(),
    state         text not null default 'open' check (state in ('open', 'closed')),
    closed_at     timestamptz,
    -- > 0 is the repost signal: gone, then back under the same identity.
    reopen_count  integer not null default 0,
    last_reopened_at timestamptz,
    content_hash  text,
    raw           jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    unique (source, board_token, posting_id)
);

create index postings_organization_id_idx on pipeline.postings (organization_id);
create index postings_board_id_idx on pipeline.postings (board_id);
create index postings_state_idx on pipeline.postings (state);
create index postings_first_published_at_idx on pipeline.postings (first_published_at);
create index postings_open_published_idx
    on pipeline.postings (first_published_at) where state = 'open';

comment on column pipeline.postings.first_published_at is
    'The ATS provider''s own posting date, and the fact the outbound pitch quotes. Never overwrite with an observation of ours.';
comment on column pipeline.postings.reopen_count is
    'Incremented each time a closed posting reappears under the same natural key. The "quietly reposted" signal.';

-- -------------------------------------------------------- posting_snapshots
-- CHANGE-ONLY, not daily. A daily row per posting would be ~10k rows/day at
-- watchlist scale, millions a year, to record that nothing happened — while
-- "still open" is already answered exactly by first_published_at + last_seen_at
-- + state. So a snapshot is written when a posting appears, changes, closes or
-- returns. Nothing the signals need is lost; the free tier survives.

create table pipeline.posting_snapshots (
    id            bigint generated always as identity primary key,
    posting_id    uuid not null references pipeline.postings (id) on delete cascade,
    run_id        uuid references pipeline.poll_runs (id) on delete set null,
    observed_at   timestamptz not null default now(),
    present       boolean not null,
    title         text,
    location      text,
    employment_type text,
    content_hash  text,
    raw           jsonb
);

create index posting_snapshots_posting_id_observed_at_idx
    on pipeline.posting_snapshots (posting_id, observed_at desc);

comment on table pipeline.posting_snapshots is
    'Append-only history, written on change rather than on schedule. See the header comment for why daily rows were rejected.';

-- ----------------------------------------------------------- posting_events
-- The signal ledger. Everything downstream (scoring, drafting, the weekly
-- report) reads this rather than re-deriving lifecycle from snapshots.

create table pipeline.posting_events (
    id            bigint generated always as identity primary key,
    posting_id    uuid not null references pipeline.postings (id) on delete cascade,
    organization_id uuid not null references pipeline.organizations (id) on delete cascade,
    run_id        uuid references pipeline.poll_runs (id) on delete set null,
    event_type    text not null check (event_type in
                      ('appeared', 'closed', 'reopened',
                       'title_changed', 'location_changed', 'employment_type_changed')),
    occurred_at   timestamptz not null default now(),
    detail        jsonb
);

create index posting_events_posting_id_idx on pipeline.posting_events (posting_id);
create index posting_events_organization_id_occurred_at_idx
    on pipeline.posting_events (organization_id, occurred_at desc);
create index posting_events_type_occurred_at_idx
    on pipeline.posting_events (event_type, occurred_at desc);

-- ------------------------------------------------------------- updated_at

create or replace function pipeline.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
    new.updated_at = now();
    return new;
end;
$fn$;

create trigger organizations_set_updated_at before update on pipeline.organizations
    for each row execute function pipeline.set_updated_at();
create trigger ats_boards_set_updated_at before update on pipeline.ats_boards
    for each row execute function pipeline.set_updated_at();
create trigger postings_set_updated_at before update on pipeline.postings
    for each row execute function pipeline.set_updated_at();

-- ------------------------------------------------------------------- views
-- Read surfaces for the operator. Deliberately thin: they name things the
-- pitch already names, so a query reads like the sentence it supports.

create view pipeline.open_postings as
    select p.id,
           o.slug  as company,
           o.name  as company_name,
           p.source,
           p.title,
           p.location,
           p.employment_type,
           p.url,
           p.first_published_at,
           p.first_seen_at,
           p.last_seen_at,
           p.reopen_count,
           -- coalesce, not silent substitution: the provider's date where it
           -- exists, our own first sighting where it does not.
           -- days_open_is_observed says which, so a claim is never quoted
           -- without knowing where its date came from.
           (current_date - coalesce(p.first_published_at, p.first_seen_at)::date) as days_open,
           (p.first_published_at is null) as days_open_is_observed
      from pipeline.postings p
      join pipeline.organizations o on o.id = p.organization_id
     where p.state = 'open';

comment on view pipeline.open_postings is
    'Every currently-open posting with its age. days_open_is_observed = true means the ATS published no date and the age is only "since we started watching" — do not quote those in outbound.';

create view pipeline.stale_openings as
    select * from pipeline.open_postings
     where days_open >= 60
     order by days_open desc;

comment on view pipeline.stale_openings is
    'The primary signal: roles open 60+ days. Computable on day one from provider dates (decisions.md 2026-08-17).';

create view pipeline.repost_signals as
    select p.id,
           o.slug as company,
           p.title,
           p.location,
           p.url,
           p.reopen_count,
           p.last_reopened_at,
           p.first_published_at,
           p.state
      from pipeline.postings p
      join pipeline.organizations o on o.id = p.organization_id
     where p.reopen_count > 0
     order by p.last_reopened_at desc;

comment on view pipeline.repost_signals is
    'Postings that vanished and came back under the same identity. Needs accumulated history — this is what the daily clock is for.';

create view pipeline.board_health as
    select b.id as board_id,
           o.slug as company,
           b.source,
           b.board_token,
           b.active,
           b.last_polled_at,
           b.last_ok_at,
           b.consecutive_failures,
           (select count(*) from pipeline.postings p
             where p.board_id = b.id and p.state = 'open') as open_postings
      from pipeline.ats_boards b
      join pipeline.organizations o on o.id = b.organization_id
     order by b.consecutive_failures desc, b.last_ok_at nulls first;

comment on view pipeline.board_health is
    'Which boards are rotting. A board whose last_ok_at is stale is losing signal silently, which is the failure mode that costs the most.';

grant all on all tables in schema pipeline to service_role;
grant usage, select on all sequences in schema pipeline to service_role;

-- RLS on every table: the pipeline schema is not exposed over HTTP, but the
-- tables carry it anyway so that exposing the schema later cannot silently
-- publish operator data. No policies exist, so every role except service_role
-- (which bypasses RLS) reads nothing.
alter table pipeline.organizations     enable row level security;
alter table pipeline.ats_boards        enable row level security;
alter table pipeline.poll_runs         enable row level security;
alter table pipeline.postings          enable row level security;
alter table pipeline.posting_snapshots enable row level security;
alter table pipeline.posting_events    enable row level security;
