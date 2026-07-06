-- Security fix: stop exposing every user's email address to every other user.
--
-- profiles.display_name is readable by all authenticated users (shared
-- household UI, policy "profiles_select_all"). handle_new_user() previously
-- defaulted display_name to the full email when no display name was supplied,
-- and the app never supplies one -- so display_name WAS the email for every
-- account, letting any signed-in user harvest all users' emails via
-- `select * from profiles`.
--
-- Default to the email's local-part instead (far less sensitive), and let
-- users set a real display name later.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(new.email, '@', 1)
    )
  );
  return new;
end;
$$;

-- Backfill: scrub any existing display_name that is exactly the account's
-- email (left over from the old default) down to the local-part.
update public.profiles p
set display_name = split_part(u.email, '@', 1)
from auth.users u
where p.id = u.id
  and p.display_name = u.email;
