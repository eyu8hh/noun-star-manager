-- Allow assigned coaches to manage the sporting records for their own teams.
-- The club manager remains the owner of all club data; coach accounts never become data owners.
-- Finance, club administration, player master records, and account management stay manager-only.

create or replace function public.nsm_coach_can_write_team(p_owner_id uuid, p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.team_coaches tc on tc.coach_user_id = p.id
    join public.teams t on t.id = tc.team_id
    where p.id = (select auth.uid())
      and p.role = 'coach'
      and t.id = p_team_id
      and t.owner_id = p_owner_id
      and tc.owner_id = p_owner_id
  );
$$;

create or replace function public.nsm_coach_can_write_match(p_owner_id uuid, p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and m.owner_id = p_owner_id
      and public.nsm_coach_can_write_team(m.owner_id, m.team_id)
  );
$$;

create or replace function public.nsm_coach_can_write_training_session(p_owner_id uuid, p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.training_sessions s
    where s.id = p_session_id
      and s.owner_id = p_owner_id
      and public.nsm_coach_can_write_team(s.owner_id, s.team_id)
  );
$$;

create or replace function public.nsm_coach_can_write_player(p_owner_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.players p
    join public.team_players tp on tp.player_id = p.id and tp.is_current = true
    join public.teams t on t.id = tp.team_id
    where p.id = p_player_id
      and p.owner_id = p_owner_id
      and public.nsm_coach_can_write_team(t.owner_id, t.id)
  );
$$;

revoke all on function public.nsm_coach_can_write_team(uuid, uuid) from public, anon;
revoke all on function public.nsm_coach_can_write_match(uuid, uuid) from public, anon;
revoke all on function public.nsm_coach_can_write_training_session(uuid, uuid) from public, anon;
revoke all on function public.nsm_coach_can_write_player(uuid, uuid) from public, anon;
grant execute on function public.nsm_coach_can_write_team(uuid, uuid) to authenticated, service_role;
grant execute on function public.nsm_coach_can_write_match(uuid, uuid) to authenticated, service_role;
grant execute on function public.nsm_coach_can_write_training_session(uuid, uuid) to authenticated, service_role;
grant execute on function public.nsm_coach_can_write_player(uuid, uuid) to authenticated, service_role;

-- Keep child rows under the club owner's ownership, not the coach's personal account.
create or replace function public.nsm_normalize_assigned_coach_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_team_id uuid;
  v_owner_id uuid;
begin
  select p.role into v_role
  from public.profiles p
  where p.id = (select auth.uid());

  if coalesce(v_role, '') <> 'coach' then
    return new;
  end if;

  case tg_table_name
    when 'matches', 'training_sessions' then
      v_team_id := (to_jsonb(new) ->> 'team_id')::uuid;
    when 'match_events', 'match_lineups' then
      select m.team_id, m.owner_id into v_team_id, v_owner_id
      from public.matches m
      where m.id = (to_jsonb(new) ->> 'match_id')::uuid;
    when 'training_attendance' then
      select s.team_id, s.owner_id into v_team_id, v_owner_id
      from public.training_sessions s
      where s.id = (to_jsonb(new) ->> 'session_id')::uuid;
    when 'injuries', 'absences', 'suspensions' then
      select t.id, t.owner_id into v_team_id, v_owner_id
      from public.team_players tp
      join public.teams t on t.id = tp.team_id
      where tp.player_id = (to_jsonb(new) ->> 'player_id')::uuid
        and tp.is_current = true
        and public.nsm_coach_can_write_team(t.owner_id, t.id)
      order by tp.joined_on desc
      limit 1;
    else
      return new;
  end case;

  if v_owner_id is null and v_team_id is not null then
    select t.owner_id into v_owner_id
    from public.teams t
    where t.id = v_team_id;
  end if;

  if v_team_id is null or v_owner_id is null
     or not public.nsm_coach_can_write_team(v_owner_id, v_team_id) then
    raise exception 'Coach is not assigned to this team' using errcode = '42501';
  end if;

  new.owner_id := v_owner_id;
  return new;
end;
$$;

revoke all on function public.nsm_normalize_assigned_coach_owner() from public, anon, authenticated;

-- The generic related-owner guard now accepts an assigned coach only for
-- team-scoped sporting records. Every referenced row must still share the
-- club owner's id, preventing cross-club references.
create or replace function public.nsm_assert_related_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  i integer := 0;
  tbl text;
  col text;
  ref_owner uuid;
  ref_value text;
  v_team_id uuid;
begin
  if new.owner_id is null then
    raise exception 'Invalid owner' using errcode = '42501';
  end if;

  if new.owner_id <> (select auth.uid()) then
    case tg_table_name
      when 'matches', 'training_sessions' then
        v_team_id := (to_jsonb(new) ->> 'team_id')::uuid;
      when 'match_events', 'match_lineups' then
        select m.team_id into v_team_id
        from public.matches m
        where m.id = (to_jsonb(new) ->> 'match_id')::uuid
          and m.owner_id = new.owner_id;
      when 'training_attendance' then
        select s.team_id into v_team_id
        from public.training_sessions s
        where s.id = (to_jsonb(new) ->> 'session_id')::uuid
          and s.owner_id = new.owner_id;
      when 'injuries', 'absences', 'suspensions' then
        select tp.team_id into v_team_id
        from public.team_players tp
        join public.teams t on t.id = tp.team_id
        where tp.player_id = (to_jsonb(new) ->> 'player_id')::uuid
          and tp.is_current = true
          and t.owner_id = new.owner_id
          and public.nsm_coach_can_write_team(t.owner_id, t.id)
        order by tp.joined_on desc
        limit 1;
      else
        v_team_id := null;
    end case;

    if not public.nsm_coach_can_write_team(new.owner_id, v_team_id) then
      raise exception 'Invalid owner' using errcode = '42501';
    end if;
  end if;

  while i < tg_nargs loop
    tbl := tg_argv[i];
    col := tg_argv[i + 1];
    ref_value := to_jsonb(new) ->> col;
    if ref_value is not null then
      execute format('select owner_id from public.%I where id = $1', tbl)
        into ref_owner using ref_value::uuid;
      if ref_owner is null or ref_owner <> new.owner_id then
        raise exception 'Related record belongs to another owner' using errcode = '42501';
      end if;
    end if;
    i := i + 2;
  end loop;
  return new;
end;
$$;

-- These trigger names sort before the existing nsm_* reference-validation triggers.
drop trigger if exists a_nsm_coach_owner_matches on public.matches;
create trigger a_nsm_coach_owner_matches
before insert or update on public.matches
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_training_sessions on public.training_sessions;
create trigger a_nsm_coach_owner_training_sessions
before insert or update on public.training_sessions
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_match_events on public.match_events;
create trigger a_nsm_coach_owner_match_events
before insert or update on public.match_events
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_match_lineups on public.match_lineups;
create trigger a_nsm_coach_owner_match_lineups
before insert or update on public.match_lineups
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_training_attendance on public.training_attendance;
create trigger a_nsm_coach_owner_training_attendance
before insert or update on public.training_attendance
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_injuries on public.injuries;
create trigger a_nsm_coach_owner_injuries
before insert or update on public.injuries
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_absences on public.absences;
create trigger a_nsm_coach_owner_absences
before insert or update on public.absences
for each row execute function public.nsm_normalize_assigned_coach_owner();

drop trigger if exists a_nsm_coach_owner_suspensions on public.suspensions;
create trigger a_nsm_coach_owner_suspensions
before insert or update on public.suspensions
for each row execute function public.nsm_normalize_assigned_coach_owner();

-- Team-bound sports operations are writable by assigned coaches only.
drop policy if exists nsm_coach_manage_assigned_matches on public.matches;
create policy nsm_coach_manage_assigned_matches on public.matches
for all to authenticated
using (public.nsm_coach_can_write_team(owner_id, team_id))
with check (public.nsm_coach_can_write_team(owner_id, team_id));

drop policy if exists nsm_coach_manage_assigned_match_lineups on public.match_lineups;
create policy nsm_coach_manage_assigned_match_lineups on public.match_lineups
for all to authenticated
using (public.nsm_coach_can_write_match(owner_id, match_id))
with check (public.nsm_coach_can_write_match(owner_id, match_id));

drop policy if exists nsm_coach_manage_assigned_match_events on public.match_events;
create policy nsm_coach_manage_assigned_match_events on public.match_events
for all to authenticated
using (public.nsm_coach_can_write_match(owner_id, match_id))
with check (public.nsm_coach_can_write_match(owner_id, match_id));

drop policy if exists nsm_coach_manage_assigned_training_sessions on public.training_sessions;
create policy nsm_coach_manage_assigned_training_sessions on public.training_sessions
for all to authenticated
using (public.nsm_coach_can_write_team(owner_id, team_id))
with check (public.nsm_coach_can_write_team(owner_id, team_id));

drop policy if exists nsm_coach_manage_assigned_training_attendance on public.training_attendance;
create policy nsm_coach_manage_assigned_training_attendance on public.training_attendance
for all to authenticated
using (public.nsm_coach_can_write_training_session(owner_id, session_id))
with check (public.nsm_coach_can_write_training_session(owner_id, session_id));

drop policy if exists nsm_coach_manage_assigned_injuries on public.injuries;
create policy nsm_coach_manage_assigned_injuries on public.injuries
for all to authenticated
using (public.nsm_coach_can_write_player(owner_id, player_id))
with check (public.nsm_coach_can_write_player(owner_id, player_id));

drop policy if exists nsm_coach_manage_assigned_absences on public.absences;
create policy nsm_coach_manage_assigned_absences on public.absences
for all to authenticated
using (public.nsm_coach_can_write_player(owner_id, player_id))
with check (public.nsm_coach_can_write_player(owner_id, player_id));

drop policy if exists nsm_coach_manage_assigned_suspensions on public.suspensions;
create policy nsm_coach_manage_assigned_suspensions on public.suspensions
for all to authenticated
using (public.nsm_coach_can_write_player(owner_id, player_id))
with check (public.nsm_coach_can_write_player(owner_id, player_id));
