-- Grocery list becomes account-synced (reverses the earlier UserDefaults-only
-- decision in DECISIONS.md, 2026-07-06): the user now wants their list to
-- follow their account across devices, and to hold a checklist with per-item
-- checked state and food categories. That is real per-user state, so it lives
-- in Postgres like meal_plans/recipe_ratings — private per user, RLS-enforced.
--
-- Each row is a concrete, standalone item (unlike ingredients, which are
-- recipe-scoped): items typed in directly, or snapshotted from a recipe's
-- ingredient. `source_recipe_id`/`source_recipe_title` remember where an item
-- came from so the "group by recipe" view has a heading; the title is
-- denormalized so the grouping survives a recipe rename or deletion (the FK is
-- ON DELETE SET NULL rather than CASCADE — a deleted recipe must not silently
-- empty your shopping list).
create table public.grocery_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  amount real not null default 0,
  unit text not null default '',
  -- Free-form category key set client-side by GroceryCategorizer (e.g.
  -- "produce", "dairy"); kept as text, not an enum, so the app can refine its
  -- categorization vocabulary without a migration.
  category text not null default 'other',
  is_checked boolean not null default false,
  source_recipe_id bigint references public.recipes (id) on delete set null,
  source_recipe_title text,
  created_at timestamptz not null default now()
);

create index grocery_items_user_id_idx on public.grocery_items (user_id);

alter table public.grocery_items enable row level security;

-- grocery_items: fully private per user, same shape as meal_plans/recipe_ratings.
create policy "grocery_items_all_own" on public.grocery_items
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on public.grocery_items to authenticated;
