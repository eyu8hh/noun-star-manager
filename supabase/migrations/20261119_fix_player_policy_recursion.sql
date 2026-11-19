create or replace function public.nsm_coach_can_read_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
set row_security = off
as $function$
  select exists (
    select 1
    from public.team_players tp
    join public.team_coaches tc on tc.team_id = tp.team_id
    where tp.player_id = p_player_id
      and tp.is_current = true
      and tc.coach_user_id = (select auth.uid())
  );
$function$;

revoke all on function public.nsm_coach_can_read_player(uuid) from public, anon;
grant execute on function public.nsm_coach_can_read_player(uuid) to authenticated;

drop policy if exists nsm_coach_read_players on public.players;
create policy nsm_coach_read_players
on public.players
for select
to authenticated
using (public.nsm_coach_can_read_player(id));

comment on function public.nsm_coach_can_read_player(uuid) is
'Checks coach team assignment without re-entering players/team_players RLS policies.';
