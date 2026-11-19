-- Enforce role-based ownership across the legacy owner-scoped tables.
-- Managers own club data; coaches can only work with assigned team records.
-- Coaches retain a private drill library and read access to their assigned club's sports references.

create or replace function public.nsm_coach_belongs_to_owner(p_owner_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.team_coaches tc on tc.coach_user_id=p.id
    join public.teams t on t.id=tc.team_id
    where p.id=(select auth.uid()) and p.role='coach'
      and tc.owner_id=p_owner_id and t.owner_id=p_owner_id
  );
$$;

create or replace function public.nsm_coach_can_read_club(p_club_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    join public.team_coaches tc on tc.coach_user_id=p.id
    join public.teams t on t.id=tc.team_id
    where p.id=(select auth.uid()) and p.role='coach' and t.club_id=p_club_id
  );
$$;

create or replace function public.nsm_coach_can_read_competition(p_competition_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    join public.team_coaches tc on tc.coach_user_id=p.id
    join public.competition_teams ct on ct.team_id=tc.team_id
    where p.id=(select auth.uid()) and p.role='coach'
      and ct.competition_id=p_competition_id
  ) or exists (
    select 1 from public.profiles p
    join public.team_coaches tc on tc.coach_user_id=p.id
    join public.matches m on m.team_id=tc.team_id
    where p.id=(select auth.uid()) and p.role='coach'
      and m.competition_id=p_competition_id
  );
$$;

revoke all on function public.nsm_coach_belongs_to_owner(uuid) from public,anon;
revoke all on function public.nsm_coach_can_read_club(uuid) from public,anon;
revoke all on function public.nsm_coach_can_read_competition(uuid) from public,anon;
grant execute on function public.nsm_coach_belongs_to_owner(uuid) to authenticated,service_role;
grant execute on function public.nsm_coach_can_read_club(uuid) to authenticated,service_role;
grant execute on function public.nsm_coach_can_read_competition(uuid) to authenticated,service_role;

-- Replace broad "owner_id = auth.uid()" access with manager-only ownership.
-- Assigned-coach policies are separate and remain narrowly scoped.
do $$
declare t text;
begin
  foreach t in array array[
    'absences','clubs','competition_teams','competitions','injuries',
    'match_events','match_lineups','matches','player_team_history','players',
    'settings','suspension_match_log','suspensions','team_coaches','team_players',
    'teams','training_attendance','training_drills','training_session_drills',
    'training_sessions'
  ] loop
    execute format('drop policy if exists nsm_owner_only on public.%I',t);
    execute format('drop policy if exists nsm_manager_owner_only on public.%I',t);
    execute format(
      'create policy nsm_manager_owner_only on public.%I for all to authenticated
       using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager''))
       with check (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager''))',
      t
    );
  end loop;
end;
$$;

-- Keep the legacy coach-owned club row readable while preventing coach-side
-- club creation, edits, deletion, and team/player master-data ownership.
drop policy if exists nsm_coach_read_legacy_owned_club on public.clubs;
create policy nsm_coach_read_legacy_owned_club on public.clubs
for select to authenticated
using (
  owner_id=(select auth.uid())
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='coach')
);

-- Coaches can read only the clubs and competitions connected to their assigned teams.
drop policy if exists nsm_coach_read_assigned_clubs on public.clubs;
create policy nsm_coach_read_assigned_clubs on public.clubs
for select to authenticated
using (public.nsm_coach_can_read_club(id));

drop policy if exists nsm_coach_read_assigned_competitions on public.competitions;
create policy nsm_coach_read_assigned_competitions on public.competitions
for select to authenticated
using (public.nsm_coach_can_read_competition(id));

drop policy if exists nsm_coach_read_assigned_competition_entries on public.competition_teams;
create policy nsm_coach_read_assigned_competition_entries on public.competition_teams
for select to authenticated
using (public.nsm_coach_can_read_competition(competition_id));

-- Private coach drill libraries remain writable by their creator.
drop policy if exists nsm_coach_manage_own_training_drills on public.training_drills;
create policy nsm_coach_manage_own_training_drills on public.training_drills
for all to authenticated
using (
  owner_id=(select auth.uid())
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='coach')
)
with check (
  owner_id=(select auth.uid())
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='coach')
);

drop policy if exists nsm_coach_read_club_training_drills on public.training_drills;
create policy nsm_coach_read_club_training_drills on public.training_drills
for select to authenticated
using (public.nsm_coach_belongs_to_owner(owner_id));

-- Assigned coaches may link their own drills (or club-owned drills) to sessions
-- for teams they coach. The link itself remains owned by the club manager.
create or replace function public.nsm_normalize_assigned_coach_owner()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_role text; v_team_id uuid; v_owner_id uuid;
begin
  select p.role into v_role from public.profiles p where p.id=(select auth.uid());
  if coalesce(v_role,'') <> 'coach' then return new; end if;
  case tg_table_name
    when 'matches','training_sessions' then
      v_team_id := (to_jsonb(new)->>'team_id')::uuid;
    when 'match_events','match_lineups' then
      select m.team_id,m.owner_id into v_team_id,v_owner_id from public.matches m
      where m.id=(to_jsonb(new)->>'match_id')::uuid;
    when 'training_attendance','training_session_drills' then
      select s.team_id,s.owner_id into v_team_id,v_owner_id from public.training_sessions s
      where s.id=(to_jsonb(new)->>'session_id')::uuid;
    when 'injuries','absences','suspensions' then
      select t.id,t.owner_id into v_team_id,v_owner_id
      from public.team_players tp join public.teams t on t.id=tp.team_id
      where tp.player_id=(to_jsonb(new)->>'player_id')::uuid and tp.is_current=true
        and public.nsm_coach_can_write_team(t.owner_id,t.id)
      order by tp.joined_on desc limit 1;
    else return new;
  end case;
  if v_owner_id is null and v_team_id is not null then
    select t.owner_id into v_owner_id from public.teams t where t.id=v_team_id;
  end if;
  if v_team_id is null or v_owner_id is null
     or not public.nsm_coach_can_write_team(v_owner_id,v_team_id) then
    raise exception 'Coach is not assigned to this team' using errcode='42501';
  end if;
  new.owner_id:=v_owner_id;
  return new;
end;
$$;

create or replace function public.nsm_assert_related_owner()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare i integer:=0; tbl text; col text; ref_owner uuid; ref_value text; v_team_id uuid;
begin
  if new.owner_id is null then raise exception 'Invalid owner' using errcode='42501'; end if;
  if new.owner_id <> (select auth.uid()) then
    case tg_table_name
      when 'matches','training_sessions' then
        v_team_id := (to_jsonb(new)->>'team_id')::uuid;
      when 'match_events','match_lineups' then
        select m.team_id into v_team_id from public.matches m
        where m.id=(to_jsonb(new)->>'match_id')::uuid and m.owner_id=new.owner_id;
      when 'training_attendance','training_session_drills' then
        select s.team_id into v_team_id from public.training_sessions s
        where s.id=(to_jsonb(new)->>'session_id')::uuid and s.owner_id=new.owner_id;
      when 'injuries','absences','suspensions' then
        select tp.team_id into v_team_id from public.team_players tp
        join public.teams t on t.id=tp.team_id
        where tp.player_id=(to_jsonb(new)->>'player_id')::uuid and tp.is_current=true
          and t.owner_id=new.owner_id and public.nsm_coach_can_write_team(t.owner_id,t.id)
        order by tp.joined_on desc limit 1;
      else v_team_id:=null;
    end case;
    if not public.nsm_coach_can_write_team(new.owner_id,v_team_id) then
      raise exception 'Invalid owner' using errcode='42501';
    end if;
  end if;
  while i < tg_nargs loop
    tbl:=tg_argv[i]; col:=tg_argv[i+1]; ref_value:=to_jsonb(new)->>col;
    if ref_value is not null then
      execute format('select owner_id from public.%I where id=$1',tbl) into ref_owner using ref_value::uuid;
      if ref_owner is null or ref_owner<>new.owner_id then
        if not (
          tg_table_name='training_session_drills'
          and tbl='training_drills'
          and ref_owner=(select auth.uid())
          and public.nsm_coach_can_write_training_session(new.owner_id,(to_jsonb(new)->>'session_id')::uuid)
        ) then
          raise exception 'Related record belongs to another owner' using errcode='42501';
        end if;
      end if;
    end if;
    i:=i+2;
  end loop;
  return new;
end;
$$;

drop trigger if exists a_nsm_coach_owner_training_session_drills on public.training_session_drills;
create trigger a_nsm_coach_owner_training_session_drills
before insert or update on public.training_session_drills
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop policy if exists nsm_coach_manage_assigned_training_session_drills on public.training_session_drills;
create policy nsm_coach_manage_assigned_training_session_drills on public.training_session_drills
for all to authenticated
using (public.nsm_coach_can_write_training_session(owner_id,session_id))
with check (public.nsm_coach_can_write_training_session(owner_id,session_id));

-- Suspension history is visible to the coach responsible for the player's current team.
drop policy if exists nsm_coach_read_assigned_suspensions on public.suspensions;
create policy nsm_coach_read_assigned_suspensions on public.suspensions
for select to authenticated
using (public.nsm_coach_can_write_player(owner_id,player_id));
