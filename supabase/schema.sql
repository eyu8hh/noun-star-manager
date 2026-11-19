-- NOUN STAR MANAGER — Supabase bootstrap schema (draft v2)
-- Fresh, dedicated Supabase project only. Review before applying.
-- Not yet executed against the live project; not production-verified.

begin;
create extension if not exists pgcrypto;

create or replace function public.nsm_touch_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at := now(); return new; end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  preferred_language text not null default 'ar' check (preferred_language in ('ar','fr')),
  role text not null default 'coach' check (role in ('manager','coach','player')),
  coach_code text,
  club_owner_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_coach_code_unique on public.profiles(lower(coach_code)) where coach_code is not null;
create index if not exists profiles_club_owner_id_idx on public.profiles(club_owner_id) where club_owner_id is not null;

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  short_name text, logo_url text, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(owner_id,name)
);
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  age_category text, season text, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(owner_id,club_id,name)
);
create table public.team_coaches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  coach_user_id uuid not null references auth.users(id) on delete cascade,
  assignment_type text not null default 'head' check (assignment_type in ('head','assistant')),
  assigned_at timestamptz not null default now(),
  unique(team_id,coach_user_id)
);
create table public.players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) > 0),
  shirt_number integer check (shirt_number between 1 and 99),
  primary_position text, birth_date date, phone text, photo_url text,
  availability text not null default 'available'
    check (availability in ('available','injured','suspended','unavailable')),
  notes text, user_id uuid references auth.users(id) on delete set null, login_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists players_user_id_unique on public.players(user_id) where user_id is not null;
create unique index if not exists players_login_code_unique on public.players(lower(login_code)) where login_code is not null;
create table public.player_profile_change_requests (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 player_id uuid not null references public.players(id) on delete cascade,
 field_key text not null check (field_key in ('full_name','shirt_number','primary_position','birth_date','phone','notes')),
 current_value text,
 proposed_value text not null check (length(trim(proposed_value)) > 0 and length(proposed_value) <= 2000),
 reason text not null default '' check (length(reason) <= 1000),
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 review_note text check (review_note is null or length(review_note) <= 1000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists player_change_requests_owner_status_idx on public.player_profile_change_requests(owner_id,status,created_at desc);
create index if not exists player_change_requests_player_idx on public.player_profile_change_requests(player_id,created_at desc);
create table public.team_players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  joined_on date not null default current_date, left_on date,
  is_current boolean not null default true, created_at timestamptz not null default now(),
  check (left_on is null or left_on >= joined_on)
);
create unique index team_players_one_current on public.team_players(player_id) where is_current;
create table public.player_team_history (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  joined_on date not null, left_on date, stats_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (left_on is null or left_on >= joined_on)
);
create table public.competitions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null, season text,
  points_win integer not null default 3 check (points_win >= 0),
  points_draw integer not null default 1 check (points_draw >= 0),
  points_loss integer not null default 0 check (points_loss >= 0),
  target_position integer check (target_position is null or target_position > 0),
  notes text, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.competition_teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  competition_id uuid not null references public.competitions(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  opponent_name text, manual_points integer not null default 0,
  remaining_matches integer not null default 0 check (remaining_matches >= 0),
  played integer not null default 0 check (played >= 0),
  won integer not null default 0 check (won >= 0),
  drawn integer not null default 0 check (drawn >= 0),
  lost integer not null default 0 check (lost >= 0),
  goals_for integer not null default 0 check (goals_for >= 0),
  goals_against integer not null default 0 check (goals_against >= 0),
  check (team_id is not null or nullif(trim(opponent_name),'') is not null)
);
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  competition_id uuid references public.competitions(id) on delete set null,
  opponent_name text not null, match_date timestamptz not null, venue text,
  duration_minutes integer not null default 90 check (duration_minutes between 1 and 300),
  home_away text not null default 'home' check (home_away in ('home','away')),
  goals_for integer check (goals_for is null or goals_for >= 0),
  goals_against integer check (goals_against is null or goals_against >= 0),
  status text not null default 'scheduled'
    check (status in ('scheduled','in_progress','finished','postponed','cancelled')),
  report text, finalized_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.match_lineups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  selection_status text not null default 'starter'
    constraint match_lineups_selection_status_check check (selection_status in ('starter','substitute','not_selected','manual')),
  position text, shirt_number integer check (shirt_number is null or shirt_number between 1 and 99),
  started_minute integer check (started_minute between 0 and 300),
  ended_minute integer check (ended_minute between 0 and 300),
  minutes_played integer check (minutes_played between 0 and 300),
  unique(match_id,player_id)
);
create table public.match_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid references public.players(id) on delete set null,
  related_player_id uuid references public.players(id) on delete set null,
  event_type text not null check (event_type in
    ('goal','assist','yellow_card','red_card','substitution_on','substitution_off','note')),
  minute integer check (minute between 0 and 300), details text,
  created_at timestamptz not null default now()
);
create table public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  session_date timestamptz not null, title text, location text, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.training_drills (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  category text not null check (category in ('technical','tactical','physical','finishing','transition')),
  age_group text, players_count integer not null default 8 check (players_count between 2 and 50),
  duration_minutes integer not null default 12 check (duration_minutes between 1 and 240),
  equipment text, objective_ar text not null, objective_fr text,
  instructions_ar text not null, instructions_fr text,
  coaching_points jsonb not null default '[]'::jsonb check (jsonb_typeof(coaching_points) = 'array'),
  match_application_ar text, match_application_fr text,
  stages jsonb not null default '[]'::jsonb check (jsonb_typeof(stages) = 'array'),
  diagram jsonb not null default '{"marks":[]}'::jsonb check (jsonb_typeof(diagram) = 'object'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.training_session_drills (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.training_sessions(id) on delete cascade,
  drill_id uuid references public.training_drills(id) on delete cascade,
  builtin_drill_key text,
  sort_order integer not null default 1 check (sort_order > 0),
  constraint training_session_drill_one_ref check ((drill_id is not null and builtin_drill_key is null) or (drill_id is null and builtin_drill_key is not null))
);

create unique index training_session_drills_custom_unique on public.training_session_drills(session_id,drill_id) where drill_id is not null;
create unique index training_session_drills_builtin_unique on public.training_session_drills(session_id,builtin_drill_key) where builtin_drill_key is not null;

create table public.training_attendance (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.training_sessions(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  attendance_status text not null default 'present'
    check (attendance_status in ('present','absent','excused','injured')),
  reason text, unique(session_id,player_id)
);
create table public.injuries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  injury_name text not null, started_on date not null default current_date,
  expected_return date, actual_return date, notes text,
  status text not null default 'active' check (status in ('active','recovered')),
  created_at timestamptz not null default now()
);
create table public.absences (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  absence_date date not null, reason text, created_at timestamptz not null default now()
);
create table public.suspensions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  reason text not null,
  incident_match_id uuid references public.matches(id) on delete set null,
  matches_remaining integer not null default 1 check (matches_remaining >= 0),
  status text not null default 'active'
    check (status in ('pending','active','served','cancelled')),
  confirmed_at timestamptz, notes text, created_at timestamptz not null default now()
);
create table public.suspension_match_log (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  suspension_id uuid not null references public.suspensions(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  matches_before integer not null check (matches_before > 0),
  status_before text not null check (status_before = 'active'),
  confirmed_at_before timestamptz,
  created_at timestamptz not null default now(),
  unique(owner_id,suspension_id,match_id)
);

create table public.settings (
  owner_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  coach_name text not null default '',
  language text not null default 'ar' check (language in ('ar','fr')),
  yellow_card_threshold integer not null default 3 check (yellow_card_threshold > 0),
  updated_at timestamptz not null default now()
);

-- Create a profile and default settings row when the coach account is created in Auth.
create or replace function public.nsm_on_auth_user_created()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles(id,display_name)
  values(new.id,coalesce(new.raw_user_meta_data ->> 'display_name',''))
  on conflict(id) do nothing;
  insert into public.settings(owner_id) values(new.id) on conflict(owner_id) do nothing;
  return new;
end $$;
create trigger nsm_auth_user_created after insert on auth.users
for each row execute function public.nsm_on_auth_user_created();

-- Backfill the manually-created coach account if it predates this bootstrap.
insert into public.profiles(id,display_name)
select id,coalesce(raw_user_meta_data ->> 'display_name','') from auth.users
on conflict(id) do nothing;
insert into public.settings(owner_id)
select id from auth.users
on conflict(owner_id) do nothing;


-- Enforce that every referenced business record belongs to the same authenticated owner.
create or replace function public.nsm_assert_related_owner()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare i integer := 0; tbl text; col text; ref_owner uuid; ref_value text;
begin
  if new.owner_id is null or new.owner_id <> auth.uid() then
    raise exception 'Invalid owner' using errcode = '42501';
  end if;
  while i < tg_nargs loop
    tbl := tg_argv[i]; col := tg_argv[i+1]; ref_value := to_jsonb(new) ->> col;
    if ref_value is not null then
      execute format('select owner_id from public.%I where id = $1',tbl)
        into ref_owner using ref_value::uuid;
      if ref_owner is null or ref_owner <> new.owner_id then
        raise exception 'Related record belongs to another owner' using errcode = '42501';
      end if;
    end if;
    i := i + 2;
  end loop;
  return new;
end $$;

create trigger nsm_teams_refs before insert or update on public.teams
for each row execute function public.nsm_assert_related_owner('clubs','club_id');
create trigger nsm_team_players_refs before insert or update on public.team_players
for each row execute function public.nsm_assert_related_owner('teams','team_id','players','player_id');
create trigger nsm_history_refs before insert or update on public.player_team_history
for each row execute function public.nsm_assert_related_owner('players','player_id','teams','team_id');
create trigger nsm_competition_teams_refs before insert or update on public.competition_teams
for each row execute function public.nsm_assert_related_owner('competitions','competition_id','teams','team_id');
create trigger nsm_matches_refs before insert or update on public.matches
for each row execute function public.nsm_assert_related_owner('teams','team_id','competitions','competition_id');
create trigger nsm_lineups_refs before insert or update on public.match_lineups
for each row execute function public.nsm_assert_related_owner('matches','match_id','players','player_id');
create trigger nsm_events_refs before insert or update on public.match_events
for each row execute function public.nsm_assert_related_owner('matches','match_id','players','player_id','players','related_player_id');
create trigger nsm_training_refs before insert or update on public.training_sessions
for each row execute function public.nsm_assert_related_owner('teams','team_id');
create trigger nsm_training_drills_owner before insert or update on public.training_drills
for each row execute function public.nsm_assert_related_owner();
create trigger nsm_training_session_drills_refs before insert or update on public.training_session_drills
for each row execute function public.nsm_assert_related_owner('training_sessions','session_id','training_drills','drill_id');
create trigger nsm_attendance_refs before insert or update on public.training_attendance
for each row execute function public.nsm_assert_related_owner('training_sessions','session_id','players','player_id');
create trigger nsm_injuries_refs before insert or update on public.injuries
for each row execute function public.nsm_assert_related_owner('players','player_id');
create trigger nsm_absences_refs before insert or update on public.absences
for each row execute function public.nsm_assert_related_owner('players','player_id');
create trigger nsm_suspensions_refs before insert or update on public.suspensions
for each row execute function public.nsm_assert_related_owner('players','player_id','matches','incident_match_id');
create trigger nsm_suspension_log_refs before insert or update on public.suspension_match_log
for each row execute function public.nsm_assert_related_owner('suspensions','suspension_id','matches','match_id');

-- Match finalization consumes one match from each active suspension belonging
-- to a currently registered player of that team. Reversals increment the current
-- balance rather than restoring a stale snapshot, so out-of-order reopening is safe.
create or replace function public.nsm_account_suspensions_for_match()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  rec record;
  inserted_id uuid;
  target_match_id uuid;
  target_owner_id uuid;
begin
  if tg_op = 'DELETE' then
    target_match_id := old.id;
    target_owner_id := old.owner_id;
  else
    target_match_id := new.id;
    target_owner_id := new.owner_id;
  end if;

  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.status = 'finished' and new.status <> 'finished') then
    for rec in
      select l.suspension_id,l.owner_id
      from public.suspension_match_log l
      where l.match_id = target_match_id and l.owner_id = target_owner_id
      order by l.created_at desc
    loop
      update public.suspensions
      set matches_remaining = matches_remaining + 1,
          status = case when status = 'served' then 'active' else status end
      where id = rec.suspension_id
        and owner_id = rec.owner_id
        and status in ('active','served');
    end loop;
    delete from public.suspension_match_log
    where match_id = target_match_id and owner_id = target_owner_id;
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op = 'UPDATE' and old.status <> 'finished' and new.status = 'finished' then
    for rec in
      select s.id,s.owner_id,s.matches_remaining,s.status,s.confirmed_at
      from public.suspensions s
      join public.team_players tp
        on tp.player_id = s.player_id
       and tp.team_id = new.team_id
       and tp.owner_id = new.owner_id
       and tp.is_current = true
      where s.owner_id = new.owner_id
        and s.status = 'active'
        and s.matches_remaining > 0
        and new.match_date >= coalesce(s.confirmed_at,s.created_at)
        and (s.incident_match_id is null or s.incident_match_id <> new.id)
      order by s.id
      for update of s
    loop
      inserted_id := null;
      insert into public.suspension_match_log
        (owner_id,suspension_id,match_id,matches_before,status_before,confirmed_at_before)
      values
        (rec.owner_id,rec.id,new.id,rec.matches_remaining,rec.status,rec.confirmed_at)
      on conflict (owner_id,suspension_id,match_id) do nothing
      returning id into inserted_id;

      if inserted_id is not null then
        update public.suspensions
        set matches_remaining = rec.matches_remaining - 1,
            status = case when rec.matches_remaining - 1 = 0 then 'served' else 'active' end
        where id = rec.id and owner_id = rec.owner_id;
      end if;
    end loop;
  end if;
  return new;
end $$;

create trigger nsm_match_suspension_accounting
before update of status on public.matches
for each row execute function public.nsm_account_suspensions_for_match();
create trigger nsm_match_suspension_delete_reversal
before delete on public.matches
for each row execute function public.nsm_account_suspensions_for_match();

alter table public.suspension_match_log enable row level security;
revoke all on table public.suspension_match_log from anon,authenticated;
grant select on table public.suspension_match_log to authenticated;
create policy nsm_suspension_log_read_own on public.suspension_match_log
for select to authenticated using (owner_id = (select auth.uid()));
revoke all on function public.nsm_account_suspensions_for_match() from public,anon,authenticated;


-- Updated-at triggers
do $$ declare t text; begin
  foreach t in array array['profiles','clubs','teams','team_coaches','players','competitions','matches','training_sessions','training_drills','settings'] loop
    execute format('create trigger nsm_touch before update on public.%I for each row execute function public.nsm_touch_updated_at()',t);
  end loop;
end $$;

-- Private row-level access. The profile uses its Auth UUID; all other tables use owner_id.
do $$ declare t text; begin
  foreach t in array array[
    'profiles','clubs','teams','team_coaches','players','player_profile_change_requests','team_players','player_team_history','competitions',
    'competition_teams','matches','match_lineups','match_events','training_sessions',
    'training_attendance','training_drills','training_session_drills','injuries','absences','suspensions','suspension_match_log','settings'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon',t);
    execute format('grant select,insert,update,delete on table public.%I to authenticated',t);
  end loop;
end $$;
create or replace function public.nsm_protect_profile_role()
returns trigger language plpgsql as $
begin
  if current_user <> 'service_role' and (new.role is distinct from old.role or new.club_owner_id is distinct from old.club_owner_id or new.coach_code is distinct from old.coach_code) then
    raise exception 'Profile role can only be changed by club administration';
  end if;
  return new;
end;
$;
create trigger nsm_protect_profile_role before update on public.profiles
for each row execute function public.nsm_protect_profile_role();

create policy nsm_manager_read_club_coaches on public.profiles for select to authenticated
using (role='coach' and club_owner_id=(select auth.uid()));
create policy nsm_player_read_own_profile on public.players for select to authenticated using (user_id=(select auth.uid()));
create policy nsm_player_read_own_team on public.team_players for select to authenticated using (exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())));
create policy nsm_player_read_own_team_details on public.teams for select to authenticated using (exists(select 1 from public.team_players tp join public.players p on p.id=tp.player_id where tp.team_id=teams.id and p.user_id=(select auth.uid()) and tp.is_current=true));
create policy nsm_player_change_request_read on public.player_profile_change_requests for select to authenticated using (exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())) or owner_id=(select auth.uid()));
create policy nsm_player_change_request_insert on public.player_profile_change_requests for insert to authenticated with check (status='pending' and reviewed_by is null and reviewed_at is null and exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid()) and p.owner_id=owner_id));
create policy nsm_player_change_request_manager_update on public.player_profile_change_requests for update to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));
create or replace function public.nsm_touch_change_request() returns trigger language plpgsql set search_path = '' as $ begin new.updated_at:=now(); return new; end $;
create trigger nsm_touch_change_request before update on public.player_profile_change_requests for each row execute function public.nsm_touch_change_request();

create policy nsm_profile_self on public.profiles for all to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));
do $$ declare t text; begin
  foreach t in array array[
    'clubs','teams','team_coaches','players','player_profile_change_requests','team_players','player_team_history','competitions',
    'competition_teams','matches','match_lineups','match_events','training_sessions',
    'training_attendance','training_drills','training_session_drills','injuries','absences','suspensions','suspension_match_log','settings'
  ] loop
    execute format('create policy nsm_owner_only on public.%I for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))',t);
  end loop;
end $$;

revoke all on function public.nsm_on_auth_user_created() from public,anon,authenticated;
revoke all on function public.nsm_assert_related_owner() from public,anon,authenticated;
revoke all on function public.nsm_touch_updated_at() from public,anon,authenticated;
revoke all on function public.nsm_account_suspensions_for_match() from public,anon,authenticated;

-- Player development, internal awards and public audience voting.
create table if not exists public.player_evaluations (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 player_id uuid not null references public.players(id) on delete cascade,
 team_id uuid not null references public.teams(id) on delete cascade,
 coach_user_id uuid not null references auth.users(id) on delete restrict,
 period_start date not null,
 technical_score smallint not null check(technical_score between 1 and 10),
 tactical_score smallint not null check(tactical_score between 1 and 10),
 physical_score smallint not null check(physical_score between 1 and 10),
 discipline_score smallint not null check(discipline_score between 1 and 10),
 coach_note text not null default '' check(length(coach_note)<=3000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(player_id,team_id,coach_user_id,period_start)
);
create index if not exists player_evaluations_player_period_idx on public.player_evaluations(player_id,period_start desc);
alter table public.player_evaluations enable row level security;
grant select,insert,update,delete on public.player_evaluations to authenticated;
drop policy if exists nsm_evaluations_read on public.player_evaluations;
create policy nsm_evaluations_read on public.player_evaluations for select to authenticated using (
 owner_id=(select auth.uid())
 or exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid()))
 or exists(select 1 from public.team_coaches tc where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()))
);
drop policy if exists nsm_evaluations_write on public.player_evaluations;
create policy nsm_evaluations_write on public.player_evaluations for all to authenticated using (
 owner_id=(select auth.uid())
 or exists(select 1 from public.team_coaches tc where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()))
) with check (
 owner_id=(select auth.uid())
 or exists(select 1 from public.team_coaches tc where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()))
);
create table if not exists public.player_monthly_votes (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 month_start date not null,
 voter_player_id uuid not null references public.players(id) on delete cascade,
 candidate_player_id uuid not null references public.players(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique(owner_id,month_start,voter_player_id),
 check(voter_player_id<>candidate_player_id)
);
create index if not exists player_monthly_votes_month_idx on public.player_monthly_votes(owner_id,month_start,candidate_player_id);
alter table public.player_monthly_votes enable row level security;
grant select,insert on public.player_monthly_votes to authenticated;
drop policy if exists nsm_monthly_votes_read on public.player_monthly_votes;
create policy nsm_monthly_votes_read on public.player_monthly_votes for select to authenticated using (owner_id=(select auth.uid()) or exists(select 1 from public.players p where p.id=voter_player_id and p.user_id=(select auth.uid())) or exists(select 1 from public.players p where p.id=candidate_player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_monthly_votes_insert on public.player_monthly_votes;
create policy nsm_monthly_votes_insert on public.player_monthly_votes for insert to authenticated with check(
 exists(select 1 from public.players voter where voter.id=player_monthly_votes.voter_player_id and voter.user_id=(select auth.uid()) and voter.owner_id=player_monthly_votes.owner_id)
 and exists(select 1 from public.team_players mine join public.team_players mate on mate.team_id=mine.team_id and mate.is_current=true join public.players candidate on candidate.id=mate.player_id where mine.player_id=player_monthly_votes.voter_player_id and mine.is_current=true and candidate.id=player_monthly_votes.candidate_player_id and candidate.owner_id=player_monthly_votes.owner_id)
 and not exists(select 1 from public.player_monthly_votes v where v.owner_id=player_monthly_votes.owner_id and v.month_start=player_monthly_votes.month_start and v.voter_player_id=player_monthly_votes.voter_player_id)
);
create or replace function public.nsm_player_vote_candidates() returns table(player_id uuid,full_name text,shirt_number integer) language sql stable security definer set search_path='' as $$ select p.id,p.full_name,p.shirt_number from public.players me join public.team_players mine on mine.player_id=me.id and mine.is_current=true join public.team_players mate on mate.team_id=mine.team_id and mate.is_current=true join public.players p on p.id=mate.player_id and p.owner_id=me.owner_id where me.user_id=(select auth.uid()) and p.id<>me.id order by p.full_name $$;
revoke all on function public.nsm_player_vote_candidates() from public;
grant execute on function public.nsm_player_vote_candidates() to authenticated;
create table if not exists public.audience_polls (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null check(length(trim(title)) between 3 and 180),
 description text not null default '' check(length(description)<=1000),
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 is_published boolean not null default false,
 created_at timestamptz not null default now(),
 check(ends_at>starts_at)
);
create table if not exists public.audience_poll_options (
 id uuid primary key default gen_random_uuid(),
 poll_id uuid not null references public.audience_polls(id) on delete cascade,
 label text not null check(length(trim(label)) between 1 and 120),
 sort_order integer not null default 0
);
create table if not exists public.audience_poll_votes (
 id uuid primary key default gen_random_uuid(),
 poll_id uuid not null references public.audience_polls(id) on delete cascade,
 option_id uuid not null references public.audience_poll_options(id) on delete cascade,
 voter_key text not null check(voter_key ~ '^[a-f0-9]{32,64}$'),
 created_at timestamptz not null default now(),
 unique(poll_id,voter_key)
);
create index if not exists audience_polls_public_idx on public.audience_polls(is_published,starts_at,ends_at);
create index if not exists audience_votes_poll_idx on public.audience_poll_votes(poll_id,option_id);
alter table public.audience_polls enable row level security;
alter table public.audience_poll_options enable row level security;
alter table public.audience_poll_votes enable row level security;
grant select,insert,update,delete on public.audience_polls to authenticated;
grant select,insert,update,delete on public.audience_poll_options to authenticated;
grant select,insert on public.audience_poll_votes to anon,authenticated;
drop policy if exists nsm_audience_poll_public_read on public.audience_polls;
create policy nsm_audience_poll_public_read on public.audience_polls for select to anon,authenticated using (is_published=true and now() between starts_at and ends_at or owner_id=(select auth.uid()));
drop policy if exists nsm_audience_poll_owner_write on public.audience_polls;
create policy nsm_audience_poll_owner_write on public.audience_polls for all to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
drop policy if exists nsm_audience_options_public_read on public.audience_poll_options;
create policy nsm_audience_options_public_read on public.audience_poll_options for select to anon,authenticated using(exists(select 1 from public.audience_polls p where p.id=poll_id and ((p.is_published=true and now() between p.starts_at and p.ends_at) or p.owner_id=(select auth.uid()))));
drop policy if exists nsm_audience_options_owner_write on public.audience_poll_options;
create policy nsm_audience_options_owner_write on public.audience_poll_options for all to authenticated using(exists(select 1 from public.audience_polls p where p.id=poll_id and p.owner_id=(select auth.uid()))) with check(exists(select 1 from public.audience_polls p where p.id=poll_id and p.owner_id=(select auth.uid())));
drop policy if exists nsm_audience_vote_read_owner on public.audience_poll_votes;
create policy nsm_audience_vote_read_owner on public.audience_poll_votes for select to authenticated using(exists(select 1 from public.audience_polls p where p.id=poll_id and p.owner_id=(select auth.uid())));
drop policy if exists nsm_audience_vote_public_insert on public.audience_poll_votes;
create policy nsm_audience_vote_public_insert on public.audience_poll_votes for insert to anon,authenticated with check(
 voter_key ~ '^[a-f0-9]{32,64}$'
 and exists(select 1 from public.audience_polls p join public.audience_poll_options o on o.poll_id=p.id where p.id=poll_id and o.id=option_id and p.is_published=true and now() between p.starts_at and p.ends_at)
);

-- Player self-service read policies and public poll result function.
drop policy if exists nsm_player_read_own_lineups on public.match_lineups;
create policy nsm_player_read_own_lineups on public.match_lineups for select to authenticated using(exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_match_events on public.match_events;
create policy nsm_player_read_own_match_events on public.match_events for select to authenticated using(exists(select 1 from public.players p where p.id=match_events.player_id and p.user_id=(select auth.uid())) or exists(select 1 from public.players p where p.id=match_events.related_player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_matches on public.matches;
create policy nsm_player_read_own_matches on public.matches for select to authenticated using(exists(select 1 from public.match_lineups ml join public.players p on p.id=ml.player_id where ml.match_id=matches.id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_training_attendance on public.training_attendance;
create policy nsm_player_read_own_training_attendance on public.training_attendance for select to authenticated using(exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_training_sessions on public.training_sessions;
create policy nsm_player_read_own_training_sessions on public.training_sessions for select to authenticated using(exists(select 1 from public.training_attendance ta join public.players p on p.id=ta.player_id where ta.session_id=training_sessions.id and p.user_id=(select auth.uid())));
create or replace function public.nsm_public_poll_results(p_poll_id uuid) returns table(option_id uuid,label text,vote_count bigint) language sql stable security definer set search_path='' as $$ select o.id,o.label,count(v.id)::bigint from public.audience_poll_options o join public.audience_polls p on p.id=o.poll_id left join public.audience_poll_votes v on v.option_id=o.id and v.poll_id=p.id where p.id=p_poll_id and p.is_published=true and now() between p.starts_at and p.ends_at group by o.id,o.label,o.sort_order order by o.sort_order,o.label $$;
revoke all on function public.nsm_public_poll_results(uuid) from public;
grant execute on function public.nsm_public_poll_results(uuid) to anon,authenticated;


commit;

-- Dashboard steps still required:
-- 1) Disable public sign-ups (Authentication > Settings/User Signups).
-- 2) Create the coach account manually in Authentication > Users.
-- 3) Use the publishable key in the browser only; never expose service_role/secret keys.
-- Match finalization/reopening/deletion has a transactional, reversible suspension ledger.
-- Standings and target-position calculations are handled by the client from registered fixtures.
