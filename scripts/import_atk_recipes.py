#!/usr/bin/env python3
"""Import ATK recipes from the old web app's export into the Supabase Postgres.

Reads the `atk_recipes.json` dump (title/description/instructions/prep_time/
servings/ingredients/tags/image_path/...) and loads recipes + their ingredients,
tags, and recipe_tags join rows into the `public` schema. Generates SQL and pipes
it to `psql` — no Python DB driver required (psycopg is not installed in this
environment) — so it works anywhere the Supabase CLI's local `psql` does.

Design notes
------------
* Recipes are imported **unowned** (`user_id = NULL`) by default: they're shared,
  read-only catalog test data. The recipes RLS model is "shared read, owner-only
  write", so a NULL owner means everyone can see them but nobody edits them via the
  app — which is exactly right for seeded test data, and keeps the import from
  coupling to any specific auth user. Pass `--owner <uuid>` to attribute them to a
  real account (which then makes them editable by that user).
* Each recipe is inserted as its own data-modifying CTE so the identity-generated
  `recipes.id` can be threaded into its ingredient and recipe_tags rows in the same
  statement (Postgres runs data-modifying CTEs to completion even when unreferenced).
* This is the *same* code path for 250 rows or the full ~14.6K — just change
  `--limit`. One transaction, so a failure rolls the whole import back.

Usage
-----
    # 250 test recipes into the running local stack (default):
    python3 scripts/import_atk_recipes.py

    # Full catalog, wiping previously-imported unowned recipes first:
    python3 scripts/import_atk_recipes.py --limit 0 --reset-catalog

    # Preview the SQL without touching the database:
    python3 scripts/import_atk_recipes.py --limit 3 --dry-run

    # Import into the linked remote project instead of local:
    python3 scripts/import_atk_recipes.py --db-url "$REMOTE_DB_URL"
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

DEFAULT_JSON = Path(
    "/Users/bvj13/source/vj-test-kitchen/atk_recipes.json"
)
DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"


def sql_str(value) -> str:
    """Render a Python value as a SQL string literal or NULL.

    standard_conforming_strings is on by default in Postgres, so backslashes are
    literal and only the single quote needs doubling.
    """
    if value is None:
        return "NULL"
    text = str(value)
    if text == "":
        return "NULL"
    return "'" + text.replace("'", "''") + "'"


def sql_int(value) -> str:
    try:
        return str(int(value))
    except (TypeError, ValueError):
        return "NULL"


def sql_float(value) -> str:
    try:
        f = float(value)
    except (TypeError, ValueError):
        return "0"
    # Guard against NaN/inf sneaking into a `real` column.
    if f != f or f in (float("inf"), float("-inf")):
        return "0"
    return repr(f)


def clean_tags(raw) -> list[str]:
    if not raw:
        return []
    seen: list[str] = []
    for t in raw:
        name = (t or "").strip()
        if name and name not in seen:
            seen.append(name)
    return seen


def recipe_statement(recipe: dict) -> str:
    """One self-contained data-modifying CTE for a single recipe + children."""
    title = (recipe.get("title") or "").strip()
    if not title:
        return ""  # title is NOT NULL; skip untitled rows

    cols = "(user_id, title, description, instructions, image_path, image_url, prep_time, servings)"
    vals = (
        "(NULL, "
        f"{sql_str(title)}, "
        f"{sql_str((recipe.get('description') or '').strip())}, "
        f"{sql_str((recipe.get('instructions') or '').strip())}, "
        f"{sql_str((recipe.get('image_path') or '').strip())}, "
        f"{sql_str((recipe.get('image_url') or '').strip())}, "
        f"{sql_int(recipe.get('prep_time'))}, "
        f"{sql_int(recipe.get('servings'))})"
    )

    ctes = [f"r AS (\n    INSERT INTO recipes {cols}\n    VALUES {vals}\n    RETURNING id\n  )"]

    ingredients = recipe.get("ingredients") or []
    ing_rows = []
    for ing in ingredients:
        name = (ing.get("name") or "").strip()
        if not name:
            continue
        ing_rows.append(f"({sql_str(name)}, {sql_float(ing.get('amount'))}, {sql_str(ing.get('unit') or '')})")
    if ing_rows:
        # unit is NOT NULL DEFAULT '' — coalesce the literal NULL back to '' here.
        ctes.append(
            "ing AS (\n"
            "    INSERT INTO ingredients (recipe_id, name, amount, unit)\n"
            "    SELECT r.id, v.name, v.amount, COALESCE(v.unit, '')\n"
            "    FROM r CROSS JOIN (VALUES\n      "
            + ",\n      ".join(ing_rows)
            + "\n    ) AS v(name, amount, unit)\n    RETURNING 1\n  )"
        )

    tags = clean_tags(recipe.get("tags"))
    with_clause = "WITH " + ",\n  ".join(ctes)

    if tags:
        tag_list = ", ".join(sql_str(t) for t in tags)
        final = (
            "INSERT INTO recipe_tags (recipe_id, tag_id)\n"
            f"SELECT r.id, t.id FROM r CROSS JOIN tags t WHERE t.name IN ({tag_list})"
        )
    else:
        # No final DML to reference `r`; a bare SELECT forces the CTE to run
        # (and `ing`, being data-modifying, runs regardless of reference).
        final = "SELECT id FROM r"

    return f"{with_clause}\n{final};"


def build_sql(recipes: list[dict], reset_catalog: bool) -> str:
    parts: list[str] = ["BEGIN;"]

    if reset_catalog:
        # Only remove previously-imported *unowned* rows; never touch recipes a
        # real user created (those have a non-NULL user_id).
        parts.append("DELETE FROM recipes WHERE user_id IS NULL;")

    # Pre-seed the shared tag vocabulary once so every recipe_tags insert can
    # resolve names to ids. tags.name is uniquely indexed.
    all_tags: list[str] = []
    for r in recipes:
        for t in clean_tags(r.get("tags")):
            if t not in all_tags:
                all_tags.append(t)
    if all_tags:
        values = ", ".join(f"({sql_str(t)})" for t in all_tags)
        parts.append(
            f"INSERT INTO tags (name) VALUES {values} ON CONFLICT (name) DO NOTHING;"
        )

    for r in recipes:
        stmt = recipe_statement(r)
        if stmt:
            parts.append(stmt)

    parts.append("COMMIT;")
    return "\n\n".join(parts) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON, help="Path to atk_recipes.json")
    parser.add_argument("--limit", type=int, default=250, help="Max recipes to import (0 = all)")
    parser.add_argument("--offset", type=int, default=0, help="Skip this many recipes from the top")
    parser.add_argument("--db-url", default=DEFAULT_DB_URL, help="Postgres connection string")
    parser.add_argument("--owner", default=None, help="Attribute recipes to this auth user UUID (default: unowned)")
    parser.add_argument("--reset-catalog", action="store_true", help="Delete existing unowned recipes first")
    parser.add_argument("--dry-run", action="store_true", help="Print SQL instead of running it")
    args = parser.parse_args()

    if not args.json.exists():
        print(f"error: {args.json} not found", file=sys.stderr)
        return 1

    with args.json.open(encoding="utf-8") as fh:
        data = json.load(fh)

    subset = data[args.offset:]
    if args.limit > 0:
        subset = subset[: args.limit]

    sql = build_sql(subset, reset_catalog=args.reset_catalog)
    if args.owner:
        # Simple, safe global swap: the only "(NULL, " occurrences are the
        # recipes VALUES tuples' user_id slot.
        sql = sql.replace("(NULL, ", f"({sql_str(args.owner)}, ")

    print(f"Prepared {len(subset)} recipes ({len(sql)} bytes of SQL).", file=sys.stderr)

    if args.dry_run:
        sys.stdout.write(sql)
        return 0

    result = subprocess.run(
        ["psql", args.db_url, "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"],
        input=sql,
        text=True,
    )
    if result.returncode != 0:
        print("import failed (psql exited non-zero)", file=sys.stderr)
        return result.returncode

    print(f"Imported {len(subset)} recipes into {args.db_url.split('@')[-1]}.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
