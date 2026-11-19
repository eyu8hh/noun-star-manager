create or replace function public.nsm_create_sponsor_finance_entry()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare agreement_row public.sponsor_agreements%rowtype; sponsor_name text; txn uuid;
begin
 if auth.uid() is null or new.owner_id<>auth.uid() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager') then raise exception 'Manager access required'; end if;
 if new.finance_transaction_id is not null then
  if not exists(select 1 from public.finance_transactions t where t.id=new.finance_transaction_id and t.owner_id=new.owner_id) then raise exception 'Linked finance transaction not found'; end if;
  return new;
 end if;
 select * into agreement_row from public.sponsor_agreements where id=new.agreement_id and owner_id=new.owner_id;
 if not found then raise exception 'Sponsor agreement not found'; end if;
 select name into sponsor_name from public.sponsors where id=agreement_row.sponsor_id and owner_id=new.owner_id;
 insert into public.finance_transactions(owner_id,kind,title,category,amount,transaction_date,payment_method,notes)
 values(new.owner_id,'income','رعاية: '||coalesce(sponsor_name,'راعي')||' — '||agreement_row.title,'sponsorship',new.amount,new.payment_date,new.payment_method,new.notes)
 returning id into txn;
 update public.sponsor_payments set finance_transaction_id=txn where id=new.id;
 return new;
end; $$;
revoke all on function public.nsm_create_sponsor_finance_entry() from public,anon,authenticated;
