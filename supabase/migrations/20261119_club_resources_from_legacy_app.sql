
-- Resources imported from the legacy NOUN STAR Android/WebView app.
create table if not exists public.club_seasons (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 name text not null check (length(trim(name)) between 2 and 80), start_date date not null, end_date date,
 status text not null default 'planned' check (status in ('planned','active','closed')), summary jsonb not null default '{}'::jsonb,
 closed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check (end_date is null or end_date >= start_date)
);
create unique index if not exists club_seasons_one_active_idx on public.club_seasons(owner_id) where status='active';
create index if not exists club_seasons_owner_dates_idx on public.club_seasons(owner_id,start_date desc);
create table if not exists public.sponsors (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 name text not null check (length(trim(name)) between 2 and 120), contact_person text, phone text, email text, address text, logo_url text,
 status text not null default 'active' check (status in ('active','inactive')), notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists sponsors_owner_name_idx on public.sponsors(owner_id,name);
create table if not exists public.sponsor_agreements (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 sponsor_id uuid not null references public.sponsors(id) on delete restrict, title text not null check (length(trim(title)) between 2 and 160),
 agreement_type text not null default 'cash' check (agreement_type in ('cash','in_kind','service')), agreed_value numeric(12,2) not null default 0 check (agreed_value >= 0),
 start_date date not null, end_date date, status text not null default 'active' check (status in ('active','expired','completed','cancelled')),
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check (end_date is null or end_date >= start_date)
);
create index if not exists sponsor_agreements_owner_idx on public.sponsor_agreements(owner_id,start_date desc);
create table if not exists public.sponsor_payments (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 agreement_id uuid not null references public.sponsor_agreements(id) on delete restrict, amount numeric(12,2) not null check (amount > 0),
 payment_date date not null default current_date, payment_method text not null default 'cash' check (payment_method in ('cash','bank','transfer','other')),
 notes text, finance_transaction_id uuid unique references public.finance_transactions(id) on delete set null, created_at timestamptz not null default now()
);
create index if not exists sponsor_payments_owner_date_idx on public.sponsor_payments(owner_id,payment_date desc);
create table if not exists public.equipment_items (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 name text not null check (length(trim(name)) between 2 and 120), category text not null default 'general',
 quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0), minimum_quantity integer not null default 0 check (minimum_quantity >= 0),
 condition text not null default 'good' check (condition in ('new','good','worn','damaged')), storage_location text, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists equipment_items_owner_idx on public.equipment_items(owner_id,name);
create table if not exists public.equipment_movements (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 item_id uuid not null references public.equipment_items(id) on delete restrict, movement_type text not null check (movement_type in ('in','out','set')),
 quantity integer not null check (quantity > 0), movement_date date not null default current_date,
 player_id uuid references public.players(id) on delete set null, team_id uuid references public.teams(id) on delete set null,
 notes text, created_at timestamptz not null default now()
);
create index if not exists equipment_movements_item_idx on public.equipment_movements(owner_id,item_id,movement_date desc);
create table if not exists public.club_kits (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 name text not null check (length(trim(name)) between 2 and 100), kit_type text not null default 'training' check (kit_type in ('home','away','third','training','goalkeeper','other')),
 season_id uuid references public.club_seasons(id) on delete set null, primary_color text, secondary_color text, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists club_kits_owner_idx on public.club_kits(owner_id,name);
create table if not exists public.kit_assignments (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 kit_id uuid not null references public.club_kits(id) on delete restrict, player_id uuid not null references public.players(id) on delete restrict,
 shirt_number text, size text, issued_at date not null default current_date, returned_at date,
 status text not null default 'issued' check (status in ('issued','returned','lost','damaged')), notes text,
 created_at timestamptz not null default now(), check (returned_at is null or returned_at >= issued_at)
);
create index if not exists kit_assignments_owner_player_idx on public.kit_assignments(owner_id,player_id,issued_at desc);
create table if not exists public.club_activity_logs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 actor_id uuid references auth.users(id) on delete set null default auth.uid(), action text not null check (length(trim(action)) between 2 and 120),
 entity_type text not null, entity_id uuid, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index if not exists club_activity_logs_owner_time_idx on public.club_activity_logs(owner_id,created_at desc);

do $$
declare t text;
begin
 foreach t in array array['club_seasons','sponsors','sponsor_agreements','sponsor_payments','equipment_items','equipment_movements','club_kits','kit_assignments','club_activity_logs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I on public.%I',t||'_manager_select',t);
  execute format('create policy %I on public.%I for select to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager''))',t||'_manager_select',t);
  execute format('drop policy if exists %I on public.%I',t||'_manager_insert',t);
  execute format('create policy %I on public.%I for insert to authenticated with check (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager''))',t||'_manager_insert',t);
  execute format('drop policy if exists %I on public.%I',t||'_manager_update',t);
  execute format('create policy %I on public.%I for update to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager'')) with check (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager''))',t||'_manager_update',t);
  execute format('drop policy if exists %I on public.%I',t||'_manager_delete',t);
  execute format('create policy %I on public.%I for delete to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role=''manager''))',t||'_manager_delete',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;

create or replace function public.nsm_validate_club_resource()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or new.owner_id<>auth.uid() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager') then raise exception 'Manager access required'; end if;
 if tg_table_name='sponsor_agreements' and not exists(select 1 from public.sponsors s where s.id=new.sponsor_id and s.owner_id=new.owner_id) then raise exception 'Sponsor does not belong to this club'; end if;
 if tg_table_name='sponsor_payments' and not exists(select 1 from public.sponsor_agreements a where a.id=new.agreement_id and a.owner_id=new.owner_id) then raise exception 'Agreement does not belong to this club'; end if;
 if tg_table_name='equipment_movements' then
  if not exists(select 1 from public.equipment_items i where i.id=new.item_id and i.owner_id=new.owner_id) then raise exception 'Equipment item does not belong to this club'; end if;
  if new.player_id is not null and not exists(select 1 from public.players p where p.id=new.player_id and p.owner_id=new.owner_id) then raise exception 'Player does not belong to this club'; end if;
  if new.team_id is not null and not exists(select 1 from public.teams t where t.id=new.team_id and t.owner_id=new.owner_id) then raise exception 'Team does not belong to this club'; end if;
 end if;
 if tg_table_name='club_kits' and new.season_id is not null and not exists(select 1 from public.club_seasons s where s.id=new.season_id and s.owner_id=new.owner_id) then raise exception 'Season does not belong to this club'; end if;
 if tg_table_name='kit_assignments' then
  if not exists(select 1 from public.club_kits k where k.id=new.kit_id and k.owner_id=new.owner_id) then raise exception 'Kit does not belong to this club'; end if;
  if not exists(select 1 from public.players p where p.id=new.player_id and p.owner_id=new.owner_id) then raise exception 'Player does not belong to this club'; end if;
 end if;
 return new;
end; $$;
drop trigger if exists nsm_resource_sponsor_agreement_guard on public.sponsor_agreements;
create trigger nsm_resource_sponsor_agreement_guard before insert or update on public.sponsor_agreements for each row execute function public.nsm_validate_club_resource();
drop trigger if exists nsm_resource_sponsor_payment_guard on public.sponsor_payments;
create trigger nsm_resource_sponsor_payment_guard before insert or update on public.sponsor_payments for each row execute function public.nsm_validate_club_resource();
drop trigger if exists nsm_resource_equipment_movement_guard on public.equipment_movements;
create trigger nsm_resource_equipment_movement_guard before insert or update on public.equipment_movements for each row execute function public.nsm_validate_club_resource();
drop trigger if exists nsm_resource_kit_guard on public.club_kits;
create trigger nsm_resource_kit_guard before insert or update on public.club_kits for each row execute function public.nsm_validate_club_resource();
drop trigger if exists nsm_resource_kit_assignment_guard on public.kit_assignments;
create trigger nsm_resource_kit_assignment_guard before insert or update on public.kit_assignments for each row execute function public.nsm_validate_club_resource();

create or replace function public.nsm_apply_equipment_movement()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare old_qty integer; new_qty integer;
begin
 if auth.uid() is null or new.owner_id<>auth.uid() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager') then raise exception 'Manager access required'; end if;
 select quantity_on_hand into old_qty from public.equipment_items where id=new.item_id and owner_id=new.owner_id for update;
 if not found then raise exception 'Equipment item not found'; end if;
 if new.movement_type='in' then new_qty:=old_qty+new.quantity; elsif new.movement_type='out' then new_qty:=old_qty-new.quantity; else new_qty:=new.quantity; end if;
 if new_qty<0 then raise exception 'Insufficient equipment quantity'; end if;
 update public.equipment_items set quantity_on_hand=new_qty,updated_at=now() where id=new.item_id and owner_id=new.owner_id;
 return new;
end; $$;
drop trigger if exists nsm_apply_equipment_movement on public.equipment_movements;
create trigger nsm_apply_equipment_movement before insert on public.equipment_movements for each row execute function public.nsm_apply_equipment_movement();

create or replace function public.nsm_create_sponsor_finance_entry()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare agreement_row public.sponsor_agreements%rowtype; sponsor_name text; txn uuid;
begin
 if auth.uid() is null or new.owner_id<>auth.uid() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager') then raise exception 'Manager access required'; end if;
 select * into agreement_row from public.sponsor_agreements where id=new.agreement_id and owner_id=new.owner_id;
 if not found then raise exception 'Sponsor agreement not found'; end if;
 select name into sponsor_name from public.sponsors where id=agreement_row.sponsor_id and owner_id=new.owner_id;
 insert into public.finance_transactions(owner_id,kind,title,category,amount,transaction_date,payment_method,notes)
 values(new.owner_id,'income','رعاية: '||coalesce(sponsor_name,'راعي')||' — '||agreement_row.title,'sponsorship',new.amount,new.payment_date,new.payment_method,new.notes) returning id into txn;
 update public.sponsor_payments set finance_transaction_id=txn where id=new.id;
 return new;
end; $$;
drop trigger if exists nsm_sponsor_payment_to_finance on public.sponsor_payments;
create trigger nsm_sponsor_payment_to_finance after insert on public.sponsor_payments for each row execute function public.nsm_create_sponsor_finance_entry();
create or replace function public.nsm_delete_sponsor_finance_entry()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if old.finance_transaction_id is not null then delete from public.finance_transactions where id=old.finance_transaction_id and owner_id=old.owner_id; end if;
 return old;
end; $$;
drop trigger if exists nsm_sponsor_payment_finance_delete on public.sponsor_payments;
create trigger nsm_sponsor_payment_finance_delete before delete on public.sponsor_payments for each row execute function public.nsm_delete_sponsor_finance_entry();

revoke all on function public.nsm_validate_club_resource() from public,anon,authenticated;
revoke all on function public.nsm_apply_equipment_movement() from public,anon,authenticated;
revoke all on function public.nsm_create_sponsor_finance_entry() from public,anon,authenticated;
revoke all on function public.nsm_delete_sponsor_finance_entry() from public,anon,authenticated;
