-- Trigram index so server-side `ilike '%...%'` title search (Recipes list,
-- Calendar recipe picker, AI Planner's search_recipes tool) stays fast as the
-- recipe catalog grows past PostgREST's default page size (Stage 8 import).
create extension if not exists pg_trgm;

create index recipes_title_trgm_idx on public.recipes using gin (title gin_trgm_ops);
