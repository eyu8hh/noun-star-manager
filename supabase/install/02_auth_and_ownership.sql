begin;

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


commit;
