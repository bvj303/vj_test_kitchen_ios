-- Server-side size limits on user-writable text, and a cap on how many tags /
-- ingredients one recipe save can carry. Closes two items from the 2026-07-06
-- security review: "no length limits on text columns" and "any user can create
-- unlimited global tags". Validation belongs on the server — the client is not
-- trusted, and PostgREST lets any authenticated user write these tables
-- directly, bypassing the app's forms.
--
-- Caps are generous on purpose: each sits well above the longest value in the
-- 14.6K-recipe catalog and user data as of 2026-09-27 (e.g. instructions max
-- 6,544 chars → cap 20,000; ingredient name max 211 → 500), so no existing row
-- is rejected — adding a CHECK validates every current row. client_logs already
-- has its own caps (20260714010000).
--
-- NULLs pass a CHECK, so optional columns need no `is null or` guard.

alter table public.recipes
  add constraint recipes_title_length check (char_length(title) <= 200),
  add constraint recipes_description_length check (char_length(description) <= 2000),
  add constraint recipes_instructions_length check (char_length(instructions) <= 20000),
  add constraint recipes_image_path_length check (char_length(image_path) <= 500),
  add constraint recipes_image_url_length check (char_length(image_url) <= 1000);

alter table public.ingredients
  add constraint ingredients_name_length check (char_length(name) <= 500),
  add constraint ingredients_unit_length check (char_length(unit) <= 50);

-- Tags are a shared global vocabulary any user can add to — keep them short and
-- non-blank.
alter table public.tags
  add constraint tags_name_length check (char_length(btrim(name)) between 1 and 60);

alter table public.grocery_items
  add constraint grocery_items_name_length check (char_length(name) <= 200),
  add constraint grocery_items_unit_length check (char_length(unit) <= 50),
  add constraint grocery_items_category_length check (char_length(category) <= 40),
  add constraint grocery_items_source_recipe_title_length check (char_length(source_recipe_title) <= 200);

alter table public.meal_plans
  add constraint meal_plans_meal_type_length check (char_length(meal_type) <= 40);

alter table public.recipe_ratings
  add constraint recipe_ratings_notes_length check (char_length(notes) <= 2000);

alter table public.profiles
  add constraint profiles_first_name_length check (char_length(first_name) <= 50),
  add constraint profiles_last_name_length check (char_length(last_name) <= 50),
  add constraint profiles_display_name_length check (char_length(display_name) <= 101),
  add constraint profiles_avatar_url_length check (char_length(avatar_url) <= 1000);

-- save_recipe: same body as 20260710010000_save_recipe_atomic, plus up-front
-- caps on tags and ingredients per save. The tag cap is what bounds how fast any
-- one user can grow the global tag table (the catalog's max is 6 tags and 33
-- ingredients per recipe). Raised as 23514 (check_violation) so the client maps
-- it with the column caps above.
create or replace function public.save_recipe(
  p_recipe_id bigint,      -- null = create a new recipe owned by the caller
  p_title text,
  p_description text,
  p_instructions text,
  p_image_path text,
  p_prep_time integer,
  p_servings integer,
  p_ingredients jsonb,     -- [{"name": text, "amount": real, "unit": text}, …]
  p_tag_names text[]
) returns bigint
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_recipe_id bigint;
begin
  if coalesce(cardinality(p_tag_names), 0) > 20 then
    raise exception 'too many tags (max 20 per recipe)' using errcode = '23514';
  end if;
  if jsonb_typeof(coalesce(p_ingredients, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_ingredients, '[]'::jsonb)) > 150 then
    raise exception 'too many ingredients (max 150 per recipe)' using errcode = '23514';
  end if;

  if p_recipe_id is null then
    insert into recipes (user_id, title, description, instructions, image_path, prep_time, servings)
    values (auth.uid(), p_title, p_description, p_instructions, p_image_path, p_prep_time, p_servings)
    returning id into v_recipe_id;
  else
    update recipes
       set title = p_title,
           description = p_description,
           instructions = p_instructions,
           image_path = p_image_path,
           prep_time = p_prep_time,
           servings = p_servings
     where id = p_recipe_id
    returning id into v_recipe_id;
    -- Under RLS a non-owned/missing recipe updates 0 rows rather than erroring;
    -- surface that as a real failure instead of silently writing children.
    if v_recipe_id is null then
      raise exception 'recipe not found or not owned by the current user'
        using errcode = '42501';
    end if;
  end if;

  -- Full replace of ingredients, matching the previous client behavior.
  delete from ingredients where recipe_id = v_recipe_id;
  insert into ingredients (recipe_id, name, amount, unit)
  select v_recipe_id, i.name, coalesce(i.amount, 0), coalesce(i.unit, '')
    from jsonb_to_recordset(coalesce(p_ingredients, '[]'::jsonb))
      as i(name text, amount real, unit text)
   where i.name is not null and length(trim(i.name)) > 0;

  -- Tags are a shared global vocabulary: find-or-create each named tag
  -- (insert-or-ignore — there is intentionally no UPDATE policy on tags),
  -- then fully replace this recipe's links.
  insert into tags (name)
  select distinct t
    from unnest(coalesce(p_tag_names, '{}'::text[])) as t
   where length(trim(t)) > 0
  on conflict (name) do nothing;
  delete from recipe_tags where recipe_id = v_recipe_id;
  insert into recipe_tags (recipe_id, tag_id)
  select v_recipe_id, tg.id
    from tags tg
   where tg.name = any(coalesce(p_tag_names, '{}'::text[]));
  return v_recipe_id;
end;
$$;

-- create or replace keeps existing grants, but restate them so this file is
-- self-describing.
revoke execute on function public.save_recipe(bigint, text, text, text, text, integer, integer, jsonb, text[]) from public, anon;
grant execute on function public.save_recipe(bigint, text, text, text, text, integer, integer, jsonb, text[]) to authenticated;
