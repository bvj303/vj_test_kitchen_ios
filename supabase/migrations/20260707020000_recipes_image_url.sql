-- Absolute external image URL for a recipe (e.g. the catalog import's Cloudinary
-- URLs). Distinct from `image_path`, which is reserved for Supabase Storage
-- object paths from user-uploaded cover photos (Stage 6): display code prefers
-- `image_url` when present, otherwise resolves `image_path` against Storage.
alter table public.recipes add column if not exists image_url text;
