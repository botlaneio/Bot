-- Move SECURITY DEFINER functions out of `public`.
--
-- Raised by the Supabase security linter after the previous migration:
--   * anon_security_definer_function_executable
--   * authenticated_security_definer_function_executable
--   * function_search_path_mutable
--
-- PostgREST exposes `public`, so anything defined there is callable over HTTP at
-- /rest/v1/rpc/<name>. Neither of these functions is an API: one is a trigger,
-- the other is internal tenancy plumbing. A private schema is not exposed by
-- PostgREST, so moving them removes the endpoint while leaving them usable from
-- policies and triggers.

create schema if not exists private;

-- Policies are evaluated as the querying role, so `authenticated` still needs to
-- reach the function. That is safe: usage on a non-exposed schema grants no HTTP
-- surface.
grant usage on schema private to authenticated, service_role;
revoke all on schema private from anon;

-- Policies depend on the function, so they go first.
drop policy if exists customers_select_self  on public.customers;
drop policy if exists orders_select_own      on public.orders;
drop policy if exists engagements_select_own on public.engagements;
drop policy if exists payments_select_own    on public.payments;
drop policy if exists documents_select_own   on public.documents;
drop policy if exists "customers read own documents" on storage.objects;

drop function if exists public.current_customer_id();

create function private.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select id from public.customers where user_id = (select auth.uid());
$$;

comment on function private.current_customer_id is
    'The customer row for the signed-in user, or null. Single point of tenancy resolution for every RLS policy. Deliberately not in `public`: it is plumbing, not an API.';

revoke all on function private.current_customer_id() from public, anon;
grant execute on function private.current_customer_id() to authenticated, service_role;

-- Recreate the policies against the private function. Still SELECT-only: no
-- insert/update/delete policy exists anywhere, so the account area is read-only
-- as a database property.
create policy customers_select_self on public.customers
    for select to authenticated
    using (user_id = (select auth.uid()));

create policy orders_select_own on public.orders
    for select to authenticated
    using (customer_id = private.current_customer_id());

create policy engagements_select_own on public.engagements
    for select to authenticated
    using (customer_id = private.current_customer_id());

create policy payments_select_own on public.payments
    for select to authenticated
    using (customer_id = private.current_customer_id());

create policy documents_select_own on public.documents
    for select to authenticated
    using (customer_id = private.current_customer_id());

create policy "customers read own documents" on storage.objects
    for select to authenticated
    using (
        bucket_id = 'documents'
        and (storage.foldername(name))[1] = private.current_customer_id()::text
    );

-- ------------------------------------------------- invite gate, relocated

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_auth_user();

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
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

comment on function private.handle_new_auth_user is
    'Invite gate. Rejects any address not already in public.customers and links the auth user to its customer row on first sign-in. Raising here rolls back the auth.users insert, so an uninvited address never becomes a user.';

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function private.handle_new_auth_user();

-- ------------------------------------------------------------ search_path

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;
