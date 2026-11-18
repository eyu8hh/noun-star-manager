-- NOUN STAR MANAGER — read-only Supabase installation verification
-- Run after schema.sql. This script does not modify data or schema.

-- 1) Expected application tables and whether RLS is enabled.
select t.table_name, coalesce(c.relrowsecurity, false) as rls_enabled,
       coalesce(c.relforcerowsecurity, false) as force_rls
from information_schema.tables t
left join pg_namespace n on n.nspname = t.table_schema
left join pg_class c on c.relnamespace = n.oid and c.relname = t.table_name
where t.table_schema = 'public'
  and t.table_name in (
    'profiles','clubs','teams','players','team_players','player_team_history',
    'competitions','competition_teams','matches','match_lineups','match_events',
    'training_sessions','training_drills','training_session_drills','training_attendance',
    'injuries','absences','suspensions','suspension_match_log','settings'
  )
order by t.table_name;

-- 2) Policies (owner-scoped; profiles are self-scoped).
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'profiles','clubs','teams','players','team_players','player_team_history',
    'competitions','competition_teams','matches','match_lineups','match_events',
    'training_sessions','training_drills','training_session_drills','training_attendance',
    'injuries','absences','suspensions','suspension_match_log','settings'
  )
order by tablename, policyname;

-- 3) Application triggers.
select c.relname as table_name, t.tgname as trigger_name, t.tgenabled
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal and t.tgname like 'nsm_%'
order by c.relname, t.tgname;

-- 4) Security-definer functions must use an empty search_path and must not be directly executable by clients.
select p.proname, p.prosecdef as security_definer, p.proconfig as function_settings,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'nsm_on_auth_user_created','nsm_assert_related_owner',
    'nsm_touch_updated_at','nsm_account_suspensions_for_match'
  )
order by p.proname;

-- 5) Coach bootstrap records.
select p.id, p.display_name, s.coach_name, s.language
from public.profiles p
left join public.settings s on s.owner_id = p.id
order by p.created_at desc;
