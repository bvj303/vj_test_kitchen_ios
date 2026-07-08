-- Normalize "0 minute" prep times in the shared catalog to NULL (unknown).
--
-- The ATK import (scripts/import_atk_recipes.py) originally stored prep_time
-- verbatim from the source dump, where ~2,900 of the 14,601 recipes (drinks,
-- salads, no-cook sauces) carry prep_time = 0 because a time was never
-- recorded. That rendered as a meaningless "0 min" in the app. The import now
-- maps 0 -> NULL (see prep_time_or_none); this cleans the rows already loaded.
--
-- Scoped to unowned catalog rows (user_id IS NULL) so a user-authored recipe
-- that legitimately has a 0 is never touched.
UPDATE recipes
SET prep_time = NULL
WHERE prep_time = 0
  AND user_id IS NULL;
