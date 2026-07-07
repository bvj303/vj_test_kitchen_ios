-- User profile pictures (avatars), publicly viewable.
--
-- Two parts: a column on profiles for the public image URL, and a public
-- Storage bucket to hold the uploaded images.
--
-- "Others can see it" is satisfied without any new policy on profiles:
-- profiles.display_name/username are already world-readable to authenticated
-- users via "profiles_select_all", so avatar_url rides along; and the bucket
-- below is public, so the image bytes themselves are fetchable by anyone
-- (including unauthenticated AsyncImage loads) — same shape as the catalog's
-- external image_url, just hosted in our own Storage.

alter table public.profiles add column if not exists avatar_url text;

-- Public read bucket for avatars. Owner-scoped writes are enforced by the
-- storage.objects policies below, keyed on the object's first path segment
-- being the uploader's user id (path convention: "<uid>/avatar.jpg").
-- 5 MiB / image-only is defense in depth; the client already downsizes to a
-- small JPEG before upload (AvatarImageProcessor). Limits live here (not just
-- config.toml, which `db push` ignores) so remote gets them too.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Anyone (anon included) may read avatar objects — this is what makes an
-- avatar visible to other users. Redundant with the bucket's public flag for
-- the public CDN path, but makes the intent explicit and covers authenticated
-- object listing.
create policy "avatars_public_read" on storage.objects
  for select
  using (bucket_id = 'avatars');

-- A user may only write (insert/update/delete) objects inside their own
-- "<uid>/…" folder, so nobody can overwrite someone else's avatar.
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
