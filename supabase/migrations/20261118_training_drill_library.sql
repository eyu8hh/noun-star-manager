-- NOUN STAR MANAGER — coach-owned tactical drill library and session plans
-- Apply after the reviewed base schema. Safe to re-run.
begin;
create table if not exists public.training_drills (
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
create table if not exists public.training_session_drills (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.training_sessions(id) on delete cascade,
  drill_id uuid references public.training_drills(id) on delete cascade,
  builtin_drill_key text,
  sort_order integer not null default 1 check (sort_order > 0),
  constraint training_session_drill_one_ref check ((drill_id is not null and builtin_drill_key is null) or (drill_id is null and builtin_drill_key is not null))
);
drop trigger if exists nsm_training_drills_owner on public.training_drills;
create trigger nsm_training_drills_owner before insert or update on public.training_drills
for each row execute function public.nsm_assert_related_owner();
drop trigger if exists nsm_training_session_drills_refs on public.training_session_drills;
create trigger nsm_training_session_drills_refs before insert or update on public.training_session_drills
for each row execute function public.nsm_assert_related_owner('training_sessions','session_id','training_drills','drill_id');
alter table public.training_session_drills alter column drill_id drop not null;
alter table public.training_session_drills add column if not exists builtin_drill_key text;
do $nsm$ begin
  if not exists (select 1 from pg_constraint where conname = 'training_session_drill_one_ref' and conrelid = 'public.training_session_drills'::regclass) then
    alter table public.training_session_drills add constraint training_session_drill_one_ref check ((drill_id is not null and builtin_drill_key is null) or (drill_id is null and builtin_drill_key is not null));
  end if;
end $nsm$;
alter table public.training_session_drills drop constraint if exists training_session_drills_session_id_drill_id_key;
create unique index if not exists training_session_drills_custom_unique on public.training_session_drills(session_id,drill_id) where drill_id is not null;
create unique index if not exists training_session_drills_builtin_unique on public.training_session_drills(session_id,builtin_drill_key) where builtin_drill_key is not null;
drop trigger if exists nsm_training_drills_touch on public.training_drills;
drop trigger if exists nsm_touch on public.training_drills;
create trigger nsm_touch before update on public.training_drills
for each row execute function public.nsm_touch_updated_at();
alter table public.training_drills enable row level security;
alter table public.training_session_drills enable row level security;
revoke all on table public.training_drills,public.training_session_drills from anon;
grant select,insert,update,delete on table public.training_drills,public.training_session_drills to authenticated;
drop policy if exists nsm_owner_only on public.training_drills;
create policy nsm_owner_only on public.training_drills for all to authenticated
using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
drop policy if exists nsm_owner_only on public.training_session_drills;
create policy nsm_owner_only on public.training_session_drills for all to authenticated
using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
revoke all on function public.nsm_assert_related_owner() from public,anon,authenticated;
revoke all on function public.nsm_touch_updated_at() from public,anon,authenticated;
commit;
