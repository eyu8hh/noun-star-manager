-- Replace per-row auth.uid() calls with statement-level initplans in policies that still use direct calls.
do $$
declare p record; updated_expr text;
begin
 for p in
  select schemaname,tablename,policyname,qual,with_check
  from pg_policies
  where schemaname='public'
    and (
      (coalesce(qual,'') ~* 'auth\.uid\(\)' and coalesce(qual,'') !~* 'select\s+auth\.uid\(\)')
      or
      (coalesce(with_check,'') ~* 'auth\.uid\(\)' and coalesce(with_check,'') !~* 'select\s+auth\.uid\(\)')
    )
 loop
  if p.qual is not null and p.qual ~* 'auth\.uid\(\)' and p.qual !~* 'select\s+auth\.uid\(\)' then
   updated_expr:=regexp_replace(p.qual,'auth\.uid\(\)','(select auth.uid())','gi');
   execute format('alter policy %I on %I.%I using (%s)',p.policyname,p.schemaname,p.tablename,updated_expr);
  end if;
  if p.with_check is not null and p.with_check ~* 'auth\.uid\(\)' and p.with_check !~* 'select\s+auth\.uid\(\)' then
   updated_expr:=regexp_replace(p.with_check,'auth\.uid\(\)','(select auth.uid())','gi');
   execute format('alter policy %I on %I.%I with check (%s)',p.policyname,p.schemaname,p.tablename,updated_expr);
  end if;
 end loop;
end $$;
