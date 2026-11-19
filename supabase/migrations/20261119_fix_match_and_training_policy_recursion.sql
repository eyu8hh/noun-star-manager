create or replace function public.nsm_player_can_read_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
set row_security = off
as $function$
  select exists (
    select 1 from public.match_lineups ml
    join public.players p on p.id = ml.player_id
    where ml.match_id = p_match_id and p.user_id = (select auth.uid())
  );
$function$;
revoke all on function public.nsm_player_can_read_match(uuid) from public, anon;
grant execute on function public.nsm_player_can_read_match(uuid) to authenticated;
drop policy if exists nsm_player_read_own_matches on public.matches;
create policy nsm_player_read_own_matches on public.matches for select to authenticated
using (public.nsm_player_can_read_match(id));

create or replace function public.nsm_player_can_read_training_session(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
set row_security = off
as $function$
  select exists (
    select 1 from public.training_attendance ta
    join public.players p on p.id = ta.player_id
    where ta.session_id = p_session_id and p.user_id = (select auth.uid())
  );
$function$;
revoke all on function public.nsm_player_can_read_training_session(uuid) from public, anon;
grant execute on function public.nsm_player_can_read_training_session(uuid) to authenticated;
drop policy if exists nsm_player_read_own_training_sessions on public.training_sessions;
create policy nsm_player_read_own_training_sessions on public.training_sessions for select to authenticated
using (public.nsm_player_can_read_training_session(id));

comment on function public.nsm_player_can_read_match(uuid) is
'Checks a player match-lineup membership without recursive matches/match_lineups RLS.';
comment on function public.nsm_player_can_read_training_session(uuid) is
'Checks a player training attendance without recursive training_sessions/training_attendance RLS.';
