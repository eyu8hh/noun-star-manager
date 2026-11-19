-- Manager-only finance ledger and player subscription dues.
create table if not exists public.finance_dues (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  player_id uuid not null references public.players(id) on delete restrict,
  title text not null default 'اشتراك الموسم',
  season text,
  amount_due numeric(12,2) not null check (amount_due > 0),
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0 and amount_paid <= amount_due),
  due_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists finance_dues_owner_date_idx on public.finance_dues(owner_id,due_date desc);
create index if not exists finance_dues_player_idx on public.finance_dues(owner_id,player_id);

create table if not exists public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  kind text not null check (kind in ('income','expense')),
  title text not null,
  category text not null,
  amount numeric(12,2) not null check (amount > 0),
  transaction_date date not null default current_date,
  payment_method text not null default 'cash' check (payment_method in ('cash','bank','transfer','other')),
  player_id uuid references public.players(id) on delete set null,
  due_id uuid references public.finance_dues(id) on delete restrict,
  notes text,
  created_at timestamptz not null default now(),
  constraint finance_due_income_only check (due_id is null or kind = 'income')
);
create index if not exists finance_transactions_owner_date_idx on public.finance_transactions(owner_id,transaction_date desc);
create index if not exists finance_transactions_due_idx on public.finance_transactions(due_id) where due_id is not null;
create index if not exists finance_transactions_kind_date_idx on public.finance_transactions(owner_id,kind,transaction_date desc);

alter table public.finance_dues enable row level security;
alter table public.finance_transactions enable row level security;

drop policy if exists finance_dues_manager_select on public.finance_dues;
create policy finance_dues_manager_select on public.finance_dues for select to authenticated
using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
drop policy if exists finance_dues_manager_insert on public.finance_dues;
create policy finance_dues_manager_insert on public.finance_dues for insert to authenticated
with check (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
drop policy if exists finance_dues_manager_update on public.finance_dues;
create policy finance_dues_manager_update on public.finance_dues for update to authenticated
using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'))
with check (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
drop policy if exists finance_dues_manager_delete on public.finance_dues;
create policy finance_dues_manager_delete on public.finance_dues for delete to authenticated
using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));

drop policy if exists finance_transactions_manager_select on public.finance_transactions;
create policy finance_transactions_manager_select on public.finance_transactions for select to authenticated
using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
drop policy if exists finance_transactions_manager_insert on public.finance_transactions;
create policy finance_transactions_manager_insert on public.finance_transactions for insert to authenticated
with check (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
drop policy if exists finance_transactions_manager_delete on public.finance_transactions;
create policy finance_transactions_manager_delete on public.finance_transactions for delete to authenticated
using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));

grant select,insert,update,delete on public.finance_dues to authenticated;
grant select,insert,delete on public.finance_transactions to authenticated;

create or replace function public.nsm_validate_finance_due_payment()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  due_row public.finance_dues%rowtype;
  already_paid numeric(12,2);
  actor_role text;
begin
  if auth.uid() is null or new.owner_id <> auth.uid() then raise exception 'Invalid finance owner'; end if;
  select role into actor_role from public.profiles where id = auth.uid();
  if actor_role <> 'manager' then raise exception 'Only the club manager can record finance transactions'; end if;
  if new.due_id is not null then
    if new.kind <> 'income' then raise exception 'A due can only be settled by an income transaction'; end if;
    select * into due_row from public.finance_dues where id = new.due_id and owner_id = new.owner_id for update;
    if not found then raise exception 'Subscription due not found'; end if;
    if new.player_id is distinct from due_row.player_id then raise exception 'Payment player does not match the due'; end if;
    select coalesce(sum(amount),0) into already_paid from public.finance_transactions where due_id = new.due_id and owner_id = new.owner_id;
    if already_paid + new.amount > due_row.amount_due then raise exception 'Payment exceeds the remaining balance'; end if;
  end if;
  return new;
end; $$;

create or replace function public.nsm_sync_finance_due_paid()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  target_due uuid;
  target_owner uuid;
  paid_total numeric(12,2);
begin
  if tg_op = 'DELETE' then target_due := old.due_id; target_owner := old.owner_id;
  else target_due := new.due_id; target_owner := new.owner_id; end if;
  if target_due is not null then
    select coalesce(sum(amount),0) into paid_total from public.finance_transactions where due_id = target_due and owner_id = target_owner;
    update public.finance_dues set amount_paid = least(paid_total, amount_due), updated_at = now() where id = target_due and owner_id = target_owner;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end; $$;

drop trigger if exists nsm_validate_finance_due_payment on public.finance_transactions;
create trigger nsm_validate_finance_due_payment before insert on public.finance_transactions
for each row execute function public.nsm_validate_finance_due_payment();
drop trigger if exists nsm_sync_finance_due_paid on public.finance_transactions;
create trigger nsm_sync_finance_due_paid after insert or delete on public.finance_transactions
for each row execute function public.nsm_sync_finance_due_paid();

revoke all on function public.nsm_validate_finance_due_payment() from public, anon, authenticated;
revoke all on function public.nsm_sync_finance_due_paid() from public, anon, authenticated;
