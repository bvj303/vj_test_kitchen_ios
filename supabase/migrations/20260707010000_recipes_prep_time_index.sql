-- Btree index on recipes.prep_time to back the Recipes list's "max prep time"
-- filter (`prep_time <= N`). Cheap insurance as the catalog grows toward the
-- Stage 8 15K+ import; the title-trigram and recipe_tags.tag_id indexes already
-- cover the list's other two filters (title search and category/tag).
create index if not exists recipes_prep_time_idx on public.recipes (prep_time);
