-- Defense in depth for the avatars owner-folder RLS.
--
-- The write policies compared the object's first path segment directly to
-- auth.uid()::text. Postgres renders a uuid as lowercase text, but clients
-- (e.g. Swift's UUID.uuidString) may produce an UPPERCASE folder — which then
-- fails the check with "new row violates row-level security policy" even
-- though it's the user's own id. The client now lowercases the path, but make
-- the comparison case-insensitive too so a stray-case path can never silently
-- break uploads again. (Read stays open; only insert/update/delete are scoped.)

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );
