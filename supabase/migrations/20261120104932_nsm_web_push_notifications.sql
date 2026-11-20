-- NOUN STAR Web Push infrastructure.
-- Sensitive values are provisioned separately in Supabase Vault; never commit them.
-- Required Vault secret names:
-- nsm_vapid_public, nsm_vapid_private, nsm_push_cron_token,
-- nsm_project_url, nsm_publishable_key.

create extension if not exists pg_cron;
create extension if not exists pg_net;

alter table public.club_notifications
  add column if not exists push_sent_at timestamptz,
  add column if not exists push_claimed_at timestamptz;

create index if not exists club_notifications_push_due_idx
  on public.club_notifications (scheduled_for, created_at)
  where push_sent_at is null and dismissed_at is null;

create table if not exists public.nsm_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_success_at timestamptz,
  constraint nsm_push_endpoint_https check (endpoint like 'https://%'),
  constraint nsm_push_p256dh_nonempty check (length(p256dh) >= 20),
  constraint nsm_push_auth_nonempty check (length(auth) >= 8)
);

create index if not exists nsm_push_subscriptions_owner_idx
  on public.nsm_push_subscriptions(owner_id);

alter table public.nsm_push_subscriptions enable row level security;
revoke all on table public.nsm_push_subscriptions from public, anon, authenticated;
grant all on table public.nsm_push_subscriptions to service_role;

create or replace function public.nsm_claim_due_push_notifications(p_batch_size integer default 50)
returns setof public.club_notifications
language sql
security definer
set search_path = ''
as $$
  with candidates as (
    select n.id
    from public.club_notifications n
    where n.push_sent_at is null
      and n.dismissed_at is null
      and coalesce(n.scheduled_for, n.created_at) <= now()
      and (n.push_claimed_at is null or n.push_claimed_at < now() - interval '10 minutes')
    order by coalesce(n.scheduled_for, n.created_at), n.created_at
    limit greatest(1, least(coalesce(p_batch_size, 50), 100))
    for update skip locked
  )
  update public.club_notifications n
     set push_claimed_at = now()
    from candidates c
   where n.id = c.id
  returning n.*;
$$;
revoke all on function public.nsm_claim_due_push_notifications(integer) from public, anon, authenticated;
grant execute on function public.nsm_claim_due_push_notifications(integer) to service_role;

create or replace function public.nsm_get_push_secrets()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.name, s.decrypted_secret), '{}'::jsonb)
  from vault.decrypted_secrets s
  where s.name in ('nsm_vapid_public', 'nsm_vapid_private', 'nsm_push_cron_token');
$$;
revoke all on function public.nsm_get_push_secrets() from public, anon, authenticated;
grant execute on function public.nsm_get_push_secrets() to service_role;

-- The schedule is active only after the required Vault values are provisioned.
select cron.unschedule(jobid)
from cron.job
where jobname = 'nsm-push-dispatch-every-minute';

select cron.schedule(
  'nsm-push-dispatch-every-minute',
  '* * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'nsm_project_url') || '/functions/v1/nsm-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'nsm_publishable_key'),
        'x-nsm-cron-token', (select decrypted_secret from vault.decrypted_secrets where name = 'nsm_push_cron_token')
      ),
      body := '{"action":"dispatch-due"}'::jsonb
    );
  $job$
);
