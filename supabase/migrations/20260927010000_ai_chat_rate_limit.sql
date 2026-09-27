-- Per-user rate limit for the Kitchen Concierge (ai-chat Edge Function).
--
-- Groq's free tier (~1,000 requests/day per model) is shared by the whole
-- household, and any authenticated user can invoke ai-chat. Without a per-user
-- cap, one runaway client (a bug, a stuck retry loop) could exhaust everyone's
-- daily quota — the "denial of wallet" the security review flagged, and the
-- deferred "Slice 4" of the concierge upgrade. See DECISIONS.md (2026-09-27).
--
-- Shape: a private log of request timestamps + one SECURITY DEFINER RPC that
-- atomically checks both windows and records the request. ai-chat calls the RPC
-- with the CALLER's own token, so it is always keyed on auth.uid() — a user can
-- only ever consume (or inspect) their own quota. Clients have NO direct access
-- to the table at all (RLS on, no policies, grants revoked).
create table public.ai_chat_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index ai_chat_requests_user_created_idx on public.ai_chat_requests (user_id, created_at desc);

alter table public.ai_chat_requests enable row level security;
-- Deliberately no policies. Hosted Supabase auto-grants ALL on new public
-- tables to anon/authenticated (the local-vs-hosted divergence, DECISIONS.md
-- 2026-07-06) — strip them so the only way in is the RPC below.
revoke all on public.ai_chat_requests from anon, authenticated;

-- Returns {"allowed": bool, "retry_after_seconds": int}. Records the request
-- only when allowed. Rows older than a day are pruned for the caller on every
-- call, so the table stays bounded at ~one day of requests per user.
create or replace function public.consume_ai_chat_quota(p_hourly_limit integer, p_daily_limit integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_hour_count integer;
  v_day_count integer;
  v_oldest timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  -- The limits come from the Edge Function; bound them so a direct call can't
  -- pass something absurd (it could only ever affect the caller's own quota).
  if p_hourly_limit is null or p_daily_limit is null
     or p_hourly_limit < 1 or p_hourly_limit > 500
     or p_daily_limit < 1 or p_daily_limit > 2000
     or p_hourly_limit > p_daily_limit then
    raise exception 'invalid quota limits' using errcode = '22023';
  end if;

  -- Serialize concurrent requests from the same user so two parallel calls
  -- can't both read "one left" and both get through.
  perform pg_advisory_xact_lock(hashtextextended('ai_chat_quota:' || v_uid::text, 0));

  delete from public.ai_chat_requests
  where user_id = v_uid and created_at < now() - interval '1 day';

  select count(*) filter (where created_at > now() - interval '1 hour'), count(*)
  into v_hour_count, v_day_count
  from public.ai_chat_requests
  where user_id = v_uid;

  if v_day_count >= p_daily_limit then
    select min(created_at) into v_oldest from public.ai_chat_requests where user_id = v_uid;
    return jsonb_build_object(
      'allowed', false,
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_oldest + interval '1 day' - now())))::integer)
    );
  end if;

  if v_hour_count >= p_hourly_limit then
    select min(created_at) into v_oldest
    from public.ai_chat_requests
    where user_id = v_uid and created_at > now() - interval '1 hour';
    return jsonb_build_object(
      'allowed', false,
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_oldest + interval '1 hour' - now())))::integer)
    );
  end if;

  insert into public.ai_chat_requests (user_id) values (v_uid);
  return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end;
$$;

revoke all on function public.consume_ai_chat_quota(integer, integer) from public, anon;
grant execute on function public.consume_ai_chat_quota(integer, integer) to authenticated;
