-- BotLane customer account area — core schema.
--
-- Three rules this schema enforces, taken from docs/decisions.md:
--
--   1. READ-ONLY. Customers select and nothing else. Every write comes from the
--      operator or a Stripe webhook via the service_role key, which bypasses
--      RLS. There are deliberately no insert/update/delete policies.
--   2. ISOLATION IN THE DATABASE. Tenancy is enforced by RLS, not by remembering
--      a WHERE clause in application code.
--   3. STRIPE IS THE SOURCE OF TRUTH FOR MONEY. `payments` is a MIRROR, kept
--      current by webhook, so a dashboard does not make live Stripe calls on
--      page load. On any disagreement, Stripe wins and the mirror is wrong.
--
-- Status columns use text + CHECK rather than Postgres enums: this schema will
-- change, and adding a value to a CHECK is a one-line migration where ALTER TYPE
-- is not.

-- ---------------------------------------------------------------- customers

create table public.customers (
    id            uuid primary key default gen_random_uuid(),
    -- The allowlist key. A person can only sign in if their email is here
    -- first; see handle_new_auth_user() in the next migration.
    email         text not null,
    -- Set on first successful sign-in. Null means invited but never logged in.
    user_id       uuid unique references auth.users (id) on delete set null,
    name          text,
    company       text,
    stripe_customer_id text unique,
    notes         text,          -- operator-only; never exposed to the customer
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- Case-insensitive uniqueness without requiring the citext extension.
create unique index customers_email_lower_key on public.customers (lower(email));

comment on table public.customers is
    'One row per paying customer. The email column is the invite allowlist: a row must exist here before that address can sign in.';
comment on column public.customers.notes is
    'Operator-only. Not exposed by any RLS policy.';

-- ------------------------------------------------------------------- orders
-- Marketplace purchases. One row per completed Stripe Checkout session.

create table public.orders (
    id            uuid primary key default gen_random_uuid(),
    customer_id   uuid not null references public.customers (id) on delete cascade,
    stripe_checkout_session_id text unique,
    stripe_payment_intent_id   text,
    -- Matches the slug in Marketplace.tsx and Stripe product metadata.slug.
    product_slug  text not null,
    product_name  text not null,
    amount_cents  integer not null check (amount_cents >= 0),
    currency      text not null default 'usd',
    -- Money and delivery are separate facts. Everything is built to order, so an
    -- order can be paid for weeks before it is delivered.
    payment_status    text not null default 'paid'
        check (payment_status in ('paid', 'refunded', 'partially_refunded')),
    fulfilment_status text not null default 'pending'
        check (fulfilment_status in ('pending', 'in_progress', 'delivered', 'cancelled')),
    purchased_at  timestamptz not null default now(),
    delivered_at  timestamptz,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    -- A delivered order must say when.
    constraint orders_delivered_has_date
        check ((fulfilment_status = 'delivered') = (delivered_at is not null))
);

create index orders_customer_id_idx on public.orders (customer_id);
create index orders_fulfilment_idx  on public.orders (fulfilment_status)
    where fulfilment_status <> 'delivered';

comment on table public.orders is
    'Marketplace purchases. payment_status and fulfilment_status are independent: built-to-order means paid long before delivered.';

-- -------------------------------------------------------------- engagements
-- Service clients. At most four at a time, per vision.md.

create table public.engagements (
    id            uuid primary key default gen_random_uuid(),
    customer_id   uuid not null references public.customers (id) on delete cascade,
    status        text not null default 'setup'
        check (status in ('setup', 'warming', 'sending', 'paused', 'ended')),
    -- Written by the operator, read by the customer. This is the "what are you
    -- actually doing" panel. It stays hand-written until the pipeline exists and
    -- can report for itself.
    status_note   text,
    stripe_subscription_id text unique,
    started_at         timestamptz not null default now(),
    -- Maintenance billing anchors to this, not to when setup was paid: warm-up
    -- takes weeks and /terms section 4 says the first maintenance invoice is
    -- issued when sending begins.
    sending_started_at timestamptz,
    ended_at           timestamptz,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    constraint engagements_ended_has_date
        check ((status = 'ended') = (ended_at is not null))
);

create index engagements_customer_id_idx on public.engagements (customer_id);

comment on column public.engagements.sending_started_at is
    'Anchor for maintenance billing. Warm-up takes weeks; do not bill maintenance before sending starts.';

-- ----------------------------------------------------------------- payments
-- A MIRROR of Stripe, not the ledger. Kept current by webhook so the dashboard
-- never makes a live Stripe call to render. Stripe wins any disagreement.

create table public.payments (
    id            uuid primary key default gen_random_uuid(),
    customer_id   uuid not null references public.customers (id) on delete cascade,
    stripe_invoice_id        text unique,
    stripe_payment_intent_id text unique,
    description   text,
    amount_cents  integer not null check (amount_cents >= 0),
    currency      text not null default 'usd',
    status        text not null
        check (status in ('draft', 'open', 'paid', 'void', 'uncollectible', 'refunded')),
    -- Populated for subscription invoices; null for one-off charges.
    period_start  timestamptz,
    period_end    timestamptz,
    due_at        timestamptz,   -- drives "next payment due"
    paid_at       timestamptz,
    -- Stripe-hosted invoice page. Cheaper and more correct than rendering our
    -- own invoice, and it always reflects Stripe's current state.
    hosted_invoice_url text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    constraint payments_has_a_stripe_id
        check (stripe_invoice_id is not null or stripe_payment_intent_id is not null)
);

create index payments_customer_id_idx on public.payments (customer_id);
create index payments_due_idx on public.payments (customer_id, due_at)
    where status = 'open';

comment on table public.payments is
    'MIRROR of Stripe, maintained by webhook. Stripe is authoritative; if these disagree, this table is wrong.';

-- ---------------------------------------------------------------- documents
-- Files: contracts, workflow files, docs, anything handed to a customer.
-- The bytes live in Supabase Storage; this table holds the metadata and is what
-- RLS is enforced against.

create table public.documents (
    id            uuid primary key default gen_random_uuid(),
    customer_id   uuid not null references public.customers (id) on delete cascade,
    -- Null for account-level documents such as a signed contract.
    order_id      uuid references public.orders (id) on delete cascade,
    kind          text not null
        check (kind in ('contract', 'workflow', 'documentation', 'invoice', 'report', 'other')),
    title         text not null,
    -- Path within the private `documents` storage bucket. By convention this
    -- MUST begin with the customer_id, because the storage policy matches on the
    -- first path segment.
    storage_path  text not null unique,
    mime_type     text,
    size_bytes    bigint check (size_bytes >= 0),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index documents_customer_id_idx on public.documents (customer_id);
create index documents_order_id_idx on public.documents (order_id);

comment on column public.documents.storage_path is
    'Must start with the customer_id: the storage RLS policy authorises on the first path segment.';

-- ------------------------------------------------------------ updated_at

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger customers_set_updated_at   before update on public.customers
    for each row execute function public.set_updated_at();
create trigger orders_set_updated_at      before update on public.orders
    for each row execute function public.set_updated_at();
create trigger engagements_set_updated_at before update on public.engagements
    for each row execute function public.set_updated_at();
create trigger payments_set_updated_at    before update on public.payments
    for each row execute function public.set_updated_at();
create trigger documents_set_updated_at   before update on public.documents
    for each row execute function public.set_updated_at();
