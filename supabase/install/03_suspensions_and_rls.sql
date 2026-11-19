begin;

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
  foreach t in array array['profiles','clubs','teams','players','competitions','matches','training_sessions','training_drills','settings'] loop
    execute format('create trigger nsm_touch before update on public.%I for each row execute function public.nsm_touch_updated_at()',t);
  end loop;
end $$;

-- Private row-level access. The profile uses its Auth UUID; all other tables use owner_id.
do $$ declare t text; begin
  foreach t in array array[
    'profiles','clubs','teams','team_coaches','players','team_players','player_team_history','competitions',
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
  if new.role is distinct from old.role and current_user <> 'service_role' then
    raise exception 'Profile role can only be changed by club administration';
  end if;
  return new;
end;
$;
drop trigger if exists nsm_protect_profile_role on public.profiles;
create trigger nsm_protect_profile_role before update on public.profiles
for each row execute function public.nsm_protect_profile_role();

create policy nsm_profile_self on public.profiles for all to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));
do $$ declare t text; begin
  foreach t in array array[
    'clubs','teams','players','team_players','player_team_history','competitions',
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
commit;
