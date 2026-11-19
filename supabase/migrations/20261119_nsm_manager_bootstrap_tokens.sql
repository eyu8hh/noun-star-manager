create table if not exists public.nsm_manager_bootstrap_tokens (
  token_hash text primary key,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.nsm_manager_bootstrap_tokens enable row level security;
revoke all on public.nsm_manager_bootstrap_tokens from public, anon, authenticated;
grant all on public.nsm_manager_bootstrap_tokens to service_role;
comment on table public.nsm_manager_bootstrap_tokens is 'One-time, short-lived bootstrap credentials for creating the initial separate club manager account. Service-role only.';
