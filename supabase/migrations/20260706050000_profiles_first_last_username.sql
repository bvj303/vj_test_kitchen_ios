-- Collect first name, last name, and a chosen username at sign-up (new
-- Create Profile screen, first step of account creation, before email/
-- password). Columns stay nullable — existing profiles predate this and
-- aren't backfilled; only new signups populate them.

alter table public.profiles
  add column first_name text,
  add column last_name text,
  add column username text;

alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[A-Za-z0-9_]{3,20}$');

-- Case-insensitive uniqueness; partial so existing null-username rows never
-- collide with each other or with a real username.
create unique index profiles_username_lower_idx
  on public.profiles (lower(username))
  where username is not null;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, first_name, last_name, username)
  values (
    new.id,
    coalesce(
      nullif(trim(concat_ws(' ', new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'last_name')), ''),
      nullif(new.raw_user_meta_data ->> 'username', ''),
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(new.email, '@', 1)
    ),
    nullif(new.raw_user_meta_data ->> 'first_name', ''),
    nullif(new.raw_user_meta_data ->> 'last_name', ''),
    nullif(new.raw_user_meta_data ->> 'username', '')
  );
  return new;
end;
$$;

-- Lets the Create Profile screen check availability before the user has a
-- session — signup isn't complete yet at that point, and `anon` otherwise has
-- zero access (see revoke_anon_access.sql). Returns only a boolean, so this
-- narrow grant doesn't reopen that lockdown; security definer so it can read
-- profiles.username despite anon having no table grant.
create function public.is_username_available(check_username text)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select not exists (
    select 1 from public.profiles where lower(username) = lower(check_username)
  );
$$;

grant execute on function public.is_username_available(text) to anon, authenticated;
