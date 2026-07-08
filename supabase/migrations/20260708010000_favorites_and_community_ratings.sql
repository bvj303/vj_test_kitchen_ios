-- Favorites (private per user) + household-visible ratings/reviews.
--
-- Two changes:
-- 1. recipe_favorites: a private per-user bookmark of a recipe (RLS all-own),
--    same shape as meal_plans / grocery_items.
-- 2. Open recipe_ratings for READ across the household so users can see each
--    other's ratings and notes (comments) on the same recipe. Writes stay
--    strictly own-only. A second FK from recipe_ratings.user_id -> profiles(id)
--    lets PostgREST embed the reviewer's public profile (display_name /
--    username / avatar_url) when selecting reviews.
--
-- NOTE (privacy): recipe_ratings.notes was previously private per user. From
-- here it's readable by any authenticated household member (that's what powers
-- "see others' comments"); the in-app editor is relabeled to say so. This is a
-- deliberate product change for a family/household app, not an oversight.

-- ============================================================================
-- recipe_favorites — private per-user favorite/bookmark
-- ============================================================================
create table public.recipe_favorites (
  user_id uuid not null references auth.users (id) on delete cascade,
  recipe_id bigint not null references public.recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

create index recipe_favorites_recipe_id_idx on public.recipe_favorites (recipe_id);

alter table public.recipe_favorites enable row level security;

create policy "recipe_favorites_all_own" on public.recipe_favorites
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, delete on public.recipe_favorites to authenticated;

-- ============================================================================
-- recipe_ratings: household-visible reads (comments), still owner-only writes
-- ============================================================================
-- The original "recipe_ratings_all_own" (FOR ALL) kept ratings strictly
-- private. Replace it with split policies: everyone reads, only the owner
-- writes — so a recipe's detail screen can show every household member's
-- rating + notes.
drop policy if exists "recipe_ratings_all_own" on public.recipe_ratings;

create policy "recipe_ratings_select_all" on public.recipe_ratings
  for select to authenticated using (true);
create policy "recipe_ratings_insert_own" on public.recipe_ratings
  for insert to authenticated with check (auth.uid() = user_id);
create policy "recipe_ratings_update_own" on public.recipe_ratings
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "recipe_ratings_delete_own" on public.recipe_ratings
  for delete to authenticated using (auth.uid() = user_id);

-- A FK to profiles so PostgREST can embed the reviewer's public profile when
-- selecting reviews (`recipe_ratings.select("*, profiles(...)")`). profiles.id
-- is a 1:1 mirror of auth.users.id, so this is always satisfiable; the existing
-- FK to auth.users stays for ownership/cascade semantics. profiles is the only
-- API-exposed target, so the embed is unambiguous.
alter table public.recipe_ratings
  add constraint recipe_ratings_user_id_profiles_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;
