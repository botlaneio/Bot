-- What the poller reads to know what to poll.
--
-- The pipeline schema is not exposed by PostgREST, deliberately, so the poller
-- cannot simply select from pipeline.ats_boards. That is the right trade: the
-- watchlist is the owned asset (it is the ICP made concrete) and it should have
-- exactly one HTTP-shaped read, not a general query surface over operator data.
--
-- Ordering is oldest-observation-first so that a run which dies halfway — a
-- runner timeout, a rate limit — degrades into "the least recently seen boards
-- were the ones that got done", rather than always starving the tail of the
-- list.

create or replace function public.pipeline_active_boards(limit_count integer default null)
returns jsonb
language sql
stable
set search_path = ''
as $fn$
    select coalesce(jsonb_agg(b), '[]'::jsonb)
      from (
        select ab.source,
               ab.board_token,
               o.slug as organization_slug,
               o.name as organization_name,
               ab.last_ok_at,
               ab.consecutive_failures
          from pipeline.ats_boards ab
          join pipeline.organizations o on o.id = ab.organization_id
         where ab.active
           and o.is_watchlisted
         order by ab.last_ok_at nulls first, ab.board_token
         limit limit_count
      ) b;
$fn$;

comment on function public.pipeline_active_boards(integer) is
    'The poll list: every active board of a watchlisted company, least-recently-succeeded first. Granted to service_role only.';

revoke all on function public.pipeline_active_boards(integer) from public, anon, authenticated;
grant execute on function public.pipeline_active_boards(integer) to service_role;
