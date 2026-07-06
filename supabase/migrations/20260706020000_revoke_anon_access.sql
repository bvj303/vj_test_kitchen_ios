-- Defense-in-depth: explicitly strip all access from the `anon` role.
-- Some hosted Supabase projects auto-grant default privileges to anon/
-- authenticated on new public-schema tables at project-creation time,
-- independent of this repo's local dev config (config.toml's
-- auto_expose_new_tables only governs the local CLI stack). Every table in
-- this app requires a signed-in user, so anon must have zero access.
revoke all on schema public from anon;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon;
