-- Invite-only access, and read-only row-level security.
--
-- NOTE: the SECURITY DEFINER functions created here were moved out of `public`
-- by the next migration (20260816150943). This file is kept as applied; read
-- both before reasoning about the current state.

-- ------------------------------------------------- invite gate on sign-up
-- There is no public sign-up. A person can only get an account if the operator
-- has already put their email in public.customers. Google OAuth and magic link
-- both funnel through auth.users, so gating here covers every method at once
-- rather than trusting each client to check.
--
-- Raising in an AFTER INSERT trigger rolls the insert back, so an uninvited
-- address never becomes a user.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_customer_id uuid;
begin
    select id into v_customer_id
      from public.customers
     where lower(email) = lower(new.email);

    if v_customer_id is null then
        raise exception 'This email address is not on the BotLane account list.'
            using errcode = '42501',
                  hint = 'Accounts are created for customers only. Email sales@botlane.io.';
    end if;

    update public.customers
       set user_id = new.id
     where id = v_customer_id;

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_auth_user();

comment on function public.handle_new_auth_user is
    'Invite gate. Rejects sign-in for any address not already in public.customers, and links the auth user to its customer row on first login.';

-- --------------------------------------------------------- tenancy helper
-- Every policy resolves tenancy through this one function, so there is a single
-- place to audit. SECURITY DEFINER because it reads public.customers, which the
-- caller cannot read past its own row.

create or replace function public.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select id from public.customers where user_id = auth.uid();
$$;

comment on function public.current_customer_id is
    'The customer row belonging to the signed-in user, or null. Single point of tenancy resolution for all RLS policies.';

revoke all on function public.current_customer_id() from public, anon;
grant execute on function public.current_customer_id() to authenticated;

-- --------------------------------------------------------------------- RLS
-- SELECT only, everywhere. No insert/update/delete policy exists for any table,
-- so an authenticated customer cannot write anything at all. Writes come from
-- the operator or the Stripe webhook using the service_role key, which bypasses
-- RLS entirely. This is what makes "the account area is read-only" a property of
-- the database rather than a promise made by the frontend.

alter table public.customers   enable row level security;
alter table public.orders      enable row level security;
alter table public.engagements enable row level security;
alter table public.payments    enable row level security;
alter table public.documents   enable row level security;

create policy customers_select_self on public.customers
    for select to authenticated
    using (user_id = auth.uid());

create policy orders_select_own on public.orders
    for select to authenticated
    using (customer_id = public.current_customer_id());

create policy engagements_select_own on public.engagements
    for select to authenticated
    using (customer_id = public.current_customer_id());

create policy payments_select_own on public.payments
    for select to authenticated
    using (customer_id = public.current_customer_id());

create policy documents_select_own on public.documents
    for select to authenticated
    using (customer_id = public.current_customer_id());

-- Column-level: withhold operator notes even from the customer's own row.
revoke select on public.customers from authenticated;
grant select (id, email, name, company, created_at) on public.customers to authenticated;

-- anon gets nothing anywhere.
revoke all on public.customers, public.orders, public.engagements,
              public.payments, public.documents from anon;

-- ------------------------------------------------------------------ storage
-- Private bucket. Document bytes are never public; the app issues short-lived
-- signed URLs, and the policy below decides who may ask for one.

insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

-- Authorises on the FIRST PATH SEGMENT, which must be the customer_id.
-- documents.storage_path carries the same convention.
create policy "customers read own documents" on storage.objects
    for select to authenticated
    using (
        bucket_id = 'documents'
        and (storage.foldername(name))[1] = public.current_customer_id()::text
    );
