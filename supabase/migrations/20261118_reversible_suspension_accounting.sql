-- NOUN STAR MANAGER — reversible suspension accounting
-- Apply once to the dedicated project after the reviewed base schema.
-- This migration is transactional and safe to re-run.

begin;

create table if not exists public.suspension_match_log (
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

create or replace function public.nsm_account_suspensions_for_match()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  rec record;
  inserted_id uuid;
  target_match_id uuid;
begin
  target_match_id := case when tg_op = 'DELETE' then old.id else new.id end;

  if tg_op = 'DELETE' or (old.status = 'finished' and new.status <> 'finished') then
    for rec in
      select l.suspension_id,l.matches_before,l.status_before,l.confirmed_at_before
      from public.suspension_match_log l
      where l.match_id = target_match_id
      order by l.created_at desc
    loop
      update public.suspensions
      set matches_remaining = rec.matches_before,
          status = rec.status_before,
          confirmed_at = rec.confirmed_at_before
      where id = rec.suspension_id
        and owner_id = case when tg_op='DELETE' then old.owner_id else new.owner_id end;
    end loop;
    delete from public.suspension_match_log where match_id = target_match_id;
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

drop trigger if exists nsm_match_suspension_accounting on public.matches;
create trigger nsm_match_suspension_accounting
before update of status on public.matches
for each row execute function public.nsm_account_suspensions_for_match();

drop trigger if exists nsm_match_suspension_delete_reversal on public.matches;
create trigger nsm_match_suspension_delete_reversal
before delete on public.matches
for each row execute function public.nsm_account_suspensions_for_match();

alter table public.suspension_match_log enable row level security;
revoke all on table public.suspension_match_log from anon,authenticated;
grant select on table public.suspension_match_log to authenticated;
drop policy if exists nsm_suspension_log_read_own on public.suspension_match_log;
create policy nsm_suspension_log_read_own on public.suspension_match_log
for select to authenticated using (owner_id = (select auth.uid()));
revoke all on function public.nsm_account_suspensions_for_match() from public,anon,authenticated;

commit;
