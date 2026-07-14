-- Observability: a persistent, retrievable sink for client-side error/fault
-- events and MetricKit crash/hang diagnostics. The app already logs everything
-- to os.Logger (Console/`log`), but that's only readable on a tethered device;
-- this table lets error-level events and crash reports survive out to a place a
-- developer can query after the fact — the "persistent, retrievable logging"
-- the engineering principles call for (not just console output).
--
-- Private per user, same RLS shape as grocery_items/meal_plans: you can only
-- write (and read back) your own rows. `user_id` DEFAULTs to auth.uid() so the
-- client never sends it — the row is auto-attributed to the signed-in caller,
-- and the WITH CHECK below still enforces it can't be spoofed to someone else.
-- An unauthenticated (anon) insert has no auth.uid(), so it hits the NOT NULL
-- and is rejected — by design, this table only captures authenticated-session
-- events (RemoteLogSink also short-circuits when signed out).
--
-- Append-only: no UPDATE/DELETE grants. `occurred_at` is when the event
-- happened on-device (MetricKit crash payloads can arrive up to ~24h later, so
-- this can trail `created_at`, the server insert time — both in UTC).
--
-- Length CHECKs are deliberate: this is the one table any authenticated user
-- can freely insert into, so cap the free-text columns to blunt storage/payload
-- abuse (addresses the "no length limits on text columns" note in the security
-- review). Write-rate limiting is tracked separately.
create table public.client_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  level text not null check (level in ('debug', 'info', 'notice', 'warning', 'error', 'fault')),
  category text not null check (length(category) <= 100),
  message text not null check (length(message) <= 4000),
  -- Structured key/value context (error type, endpoint, ids). jsonb, not text,
  -- so it can be queried/indexed later without a migration.
  metadata jsonb not null default '{}'::jsonb,
  platform text check (platform is null or length(platform) <= 20),
  app_version text check (app_version is null or length(app_version) <= 40),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Dashboard/admin reads and a user's own history both want newest-first by user.
create index client_logs_user_created_idx on public.client_logs (user_id, created_at desc);

alter table public.client_logs enable row level security;

-- Insert and read only your own rows. No update/delete: a log is append-only.
create policy "client_logs_insert_own" on public.client_logs
  for insert to authenticated
  with check (auth.uid() = user_id);

create policy "client_logs_select_own" on public.client_logs
  for select to authenticated
  using (auth.uid() = user_id);

-- Be deterministic about grants: hosted Supabase auto-grants ALL privileges to
-- `authenticated` (and `anon`) on new public-schema tables at creation, which
-- differs from the local CLI stack (the same local-vs-remote grant divergence
-- documented in DECISIONS.md, 2026-07-06). RLS already blocks update/delete
-- (no matching policy), but leaving those grants in place contradicts this
-- table's append-only intent — so strip everything, then grant back only what
-- the policies actually use.
revoke all on public.client_logs from authenticated, anon;
grant select, insert on public.client_logs to authenticated;
