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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
create table public.players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) > 0),
  shirt_number integer check (shirt_number between 1 and 99),
  primary_position text, birth_date date, phone text, photo_url text,
  availability text not null default 'available'
    check (availability in ('available','injured','suspended','unavailable')),
  notes text, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
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
    check (selection_status in ('starter','substitute','not_selected')),
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
create trigger nsm_attendance_refs before insert or update on public.training_attendance
for each row execute function public.nsm_assert_related_owner('training_sessions','session_id','players','player_id');
create trigger nsm_injuries_refs before insert or update on public.injuries
for each row execute function public.nsm_assert_related_owner('players','player_id');
create trigger nsm_absences_refs before insert or update on public.absences
for each row execute function public.nsm_assert_related_owner('players','player_id');
create trigger nsm_suspensions_refs before insert or update on public.suspensions
for each row execute function public.nsm_assert_related_owner('players','player_id','matches','incident_match_id');

-- Updated-at triggers
do $$ declare t text; begin
  foreach t in array array['profiles','clubs','teams','players','competitions','matches','training_sessions','settings'] loop
    execute format('create trigger nsm_touch before update on public.%I for each row execute function public.nsm_touch_updated_at()',t);
  end loop;
end $$;

-- Private row-level access. The profile uses its Auth UUID; all other tables use owner_id.
do $$ declare t text; begin
  foreach t in array array[
    'profiles','clubs','teams','players','team_players','player_team_history','competitions',
    'competition_teams','matches','match_lineups','match_events','training_sessions',
    'training_attendance','injuries','absences','suspensions','settings'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon',t);
    execute format('grant select,insert,update,delete on table public.%I to authenticated',t);
  end loop;
end $$;
create policy nsm_profile_self on public.profiles for all to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));
do $$ declare t text; begin
  foreach t in array array[
    'clubs','teams','players','team_players','player_team_history','competitions',
    'competition_teams','matches','match_lineups','match_events','training_sessions',
    'training_attendance','injuries','absences','suspensions','settings'
  ] loop
    execute format('create policy nsm_owner_only on public.%I for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))',t);
  end loop;
end $$;

revoke all on function public.nsm_on_auth_user_created() from public,anon,authenticated;
revoke all on function public.nsm_assert_related_owner() from public,anon,authenticated;
revoke all on function public.nsm_touch_updated_at() from public,anon,authenticated;
commit;

-- Dashboard steps still required:
-- 1) Disable public sign-ups (Authentication > Settings/User Signups).
-- 2) Create the coach account manually in Authentication > Users.
-- 3) Use the publishable key in the browser only; never expose service_role/secret keys.
-- This bootstrap does not yet implement transactional match finalization, standings
-- aggregation, or suspension decrement/reversal. Those need a separate tested migration.
