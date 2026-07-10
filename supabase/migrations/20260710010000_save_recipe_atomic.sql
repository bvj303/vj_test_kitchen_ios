-- Atomic recipe save: the recipe row, its ingredients, and its tags in ONE
-- transaction. The client previously issued 3+ separate requests (create/update
-- recipe → delete+insert ingredients → upsert tags + delete+insert recipe_tags),
-- so a network drop mid-save could leave a recipe with no ingredients (the
-- delete landed, the insert didn't) or duplicate the recipe on retry (the
-- create landed, the rest didn't, and Save was tapped again).
--
-- SECURITY INVOKER, deliberately: the function runs as the calling
-- `authenticated` user, so every statement stays subject to exactly the same
-- RLS policies the individual client calls were (create inserts with
-- user_id = auth.uid(); update/ingredients/recipe_tags writes only touch rows
-- the owner policies allow; tags insert-or-ignore matches tags_insert_any).

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

revoke execute on function public.save_recipe(bigint, text, text, text, text, integer, integer, jsonb, text[]) from public, anon;
grant execute on function public.save_recipe(bigint, text, text, text, text, integer, integer, jsonb, text[]) to authenticated;
