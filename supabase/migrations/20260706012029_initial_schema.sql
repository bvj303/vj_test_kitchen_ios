-- Initial schema for VJ Test Kitchen (iOS rebuild)
-- Model: recipes are a shared household recipe box (any authenticated user can
-- read all recipes; only the creator can edit/delete a recipe's core fields).
-- Ratings/notes are personal per user (recipe_ratings), and meal plans are
-- strictly private per user (meal_plans).

-- ============================================================================
-- profiles: 1:1 shadow of auth.users, for display names in a shared UI
-- ============================================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================================
-- shared updated_at trigger helper
-- ============================================================================
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- recipes — shared household recipe box; user_id survives creator deletion
-- (ON DELETE SET NULL) so recipes persist in the shared box.
-- ============================================================================
create table public.recipes (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users (id) on delete set null,
  title text not null,
  description text,
  instructions text,
  image_path text,
  prep_time integer,
  servings integer,
  created_at timestamptz not null default now()
);

create index recipes_user_id_idx on public.recipes (user_id);

-- ============================================================================
-- recipe_ratings — personal per-user rating + notes on a recipe. Strictly
-- private: no aggregate/average is computed, each user only sees their own.
-- ============================================================================
create table public.recipe_ratings (
  recipe_id bigint not null references public.recipes (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  rating smallint check (rating is null or (rating between 1 and 5)),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (recipe_id, user_id)
);

create index recipe_ratings_recipe_id_idx on public.recipe_ratings (recipe_id);

create trigger recipe_ratings_set_updated_at
  before update on public.recipe_ratings
  for each row execute procedure public.set_updated_at();

-- ============================================================================
-- ingredients
-- ============================================================================
create table public.ingredients (
  id bigint generated always as identity primary key,
  recipe_id bigint not null references public.recipes (id) on delete cascade,
  name text not null,
  amount real not null default 0,
  unit text not null default ''
);

create index ingredients_recipe_id_idx on public.ingredients (recipe_id);

-- ============================================================================
-- tags + recipe_tags
-- ============================================================================
create table public.tags (
  id bigint generated always as identity primary key,
  name text not null unique
);

create table public.recipe_tags (
  recipe_id bigint not null references public.recipes (id) on delete cascade,
  tag_id bigint not null references public.tags (id) on delete cascade,
  primary key (recipe_id, tag_id)
);

create index recipe_tags_tag_id_idx on public.recipe_tags (tag_id);

-- ============================================================================
-- meal_plans (private per user)
-- ============================================================================
create table public.meal_plans (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  meal_type text not null,
  recipe_id bigint not null references public.recipes (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index meal_plans_user_id_idx on public.meal_plans (user_id);

-- ============================================================================
-- RLS
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.recipes enable row level security;
alter table public.recipe_ratings enable row level security;
alter table public.ingredients enable row level security;
alter table public.tags enable row level security;
alter table public.recipe_tags enable row level security;
alter table public.meal_plans enable row level security;

-- profiles: everyone can see display names; only the owner can write their own
create policy "profiles_select_all" on public.profiles
  for select to authenticated using (true);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- recipes: shared read, owner-only write of core fields
create policy "recipes_select_all" on public.recipes
  for select to authenticated using (true);
create policy "recipes_insert_own" on public.recipes
  for insert to authenticated with check (auth.uid() = user_id);
create policy "recipes_update_own" on public.recipes
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "recipes_delete_own" on public.recipes
  for delete to authenticated using (auth.uid() = user_id);

-- recipe_ratings: fully private per user (own rating/notes only, no cross-user access)
create policy "recipe_ratings_all_own" on public.recipe_ratings
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ingredients: visible with their recipe; only the recipe's owner can write
create policy "ingredients_select_all" on public.ingredients
  for select to authenticated using (true);
create policy "ingredients_write_via_recipe_owner" on public.ingredients
  for all to authenticated
  using (exists (select 1 from public.recipes r where r.id = ingredients.recipe_id and r.user_id = auth.uid()))
  with check (exists (select 1 from public.recipes r where r.id = ingredients.recipe_id and r.user_id = auth.uid()));

-- tags: shared global vocabulary; anyone can read or add a new tag, nobody renames/deletes one
create policy "tags_select_all" on public.tags
  for select to authenticated using (true);
create policy "tags_insert_any" on public.tags
  for insert to authenticated with check (true);

-- recipe_tags: visible with their recipe; only the recipe's owner can attach/detach tags
create policy "recipe_tags_select_all" on public.recipe_tags
  for select to authenticated using (true);
create policy "recipe_tags_write_via_recipe_owner" on public.recipe_tags
  for all to authenticated
  using (exists (select 1 from public.recipes r where r.id = recipe_tags.recipe_id and r.user_id = auth.uid()))
  with check (exists (select 1 from public.recipes r where r.id = recipe_tags.recipe_id and r.user_id = auth.uid()));

-- meal_plans: fully private per user
create policy "meal_plans_all_own" on public.meal_plans
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================================
-- Grants — Supabase no longer auto-exposes new tables to API roles, so these
-- are required in addition to RLS for PostgREST access to work at all.
-- ============================================================================
grant usage on schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.recipes to authenticated;
grant select, insert, update, delete on public.recipe_ratings to authenticated;
grant select, insert, update, delete on public.ingredients to authenticated;
grant select, insert on public.tags to authenticated;
grant select, insert, delete on public.recipe_tags to authenticated;
grant select, insert, update, delete on public.meal_plans to authenticated;
