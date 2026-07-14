#!/usr/bin/env python3
"""Fetch America's Test Kitchen's own average rating for each recipe and apply
it to the `recipes.atk_rating`/`atk_rating_count` columns.

Two subcommands, mirroring import_atk_recipes.py's fetch-then-apply shape:

  fetch  Hit each recipe's public ATK page (unauthenticated — no login, no
         cookies) and pull `aggregateRating.ratingValue`/`reviewCount` out of
         the page's Recipe JSON-LD (the same structured-data block search
         engines read; confirmed present without any session). Results are
         checkpointed to a local JSON file after every recipe, so an
         interrupted run resumes instead of restarting from scratch.

  apply  Turn a fetch checkpoint into `UPDATE recipes SET atk_rating = ...`
         statements (matched by title, same convention as
         import_atk_recipes.py's --backfill-images), piped to psql.

Design notes
------------
* Deliberately unauthenticated and low-volume: no Playwright, no ATK login,
  a descriptive (not browser-spoofed) User-Agent, and a real delay between
  requests by default. This only ever reads a single public numeric field —
  it does not re-scrape or store recipe text/images.
* `--delay`/`--jitter` default to a gentle pace (14,601 recipes at ~1.3s
  apart is ~5 hours) — raise `--concurrency` and lower `--delay` at your own
  discretion, but the defaults are chosen to be a good citizen, not to
  finish quickly.
* A recipe with no ATK JSON-LD `Recipe` block at all is treated as a fetch
  *failure* (logged, retried, left out of the checkpoint) — that's the page
  not matching the expected shape. A `Recipe` block with no `aggregateRating`
  (not yet rated) is a legitimate empty result, recorded as such so it isn't
  retried forever.

Usage
-----
    # Test on a handful of recipes first:
    python3 scripts/scrape_atk_ratings.py fetch --limit 5 --output /tmp/atk_ratings_test.json

    # Full run (resumable — safe to Ctrl-C and re-run):
    python3 scripts/scrape_atk_ratings.py fetch --output atk_ratings.json

    # Preview the SQL without touching the database:
    python3 scripts/scrape_atk_ratings.py apply --json atk_ratings.json --dry-run

    # Apply to the local stack:
    python3 scripts/scrape_atk_ratings.py apply --json atk_ratings.json
"""

from __future__ import annotations

import argparse
import json
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_RECIPES_JSON = Path("/Users/bvj13/source/vj-test-kitchen/atk_recipes.json")
DEFAULT_RATINGS_JSON = Path("atk_ratings.json")
DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
DEFAULT_USER_AGENT = "VJTestKitchenRatingSync/1.0 (personal recipe app; contact: applerocks24@gmail.com)"

LD_JSON_RE = re.compile(
    r'<script\b[^>]*type=["\']application/ld\+json["\'][^>]*>([\s\S]*?)</script>',
    re.IGNORECASE,
)


def find_recipe(obj):
    """Depth-first search for the `@type: Recipe` node in a JSON-LD document
    (possibly wrapped in an `@graph` list)."""
    if not obj:
        return None
    if isinstance(obj, dict):
        if obj.get("@type") == "Recipe":
            return obj
        if isinstance(obj.get("@graph"), list):
            return find_recipe(obj["@graph"])
    elif isinstance(obj, list):
        for item in obj:
            found = find_recipe(item)
            if found:
                return found
    return None


class NoRecipeDataError(ValueError):
    """The page had no Recipe JSON-LD block at all — a real fetch failure,
    not just an unrated recipe."""


def extract_rating(html: str) -> tuple[float | None, int | None]:
    """Returns (rating, review_count), both None if the recipe simply has no
    ratings yet. Raises NoRecipeDataError if no Recipe block was found."""
    for block in LD_JSON_RE.findall(html):
        try:
            parsed = json.loads(block.strip())
        except (json.JSONDecodeError, ValueError):
            continue
        recipe = find_recipe(parsed)
        if not recipe:
            continue
        agg = recipe.get("aggregateRating")
        if not isinstance(agg, dict):
            return None, None
        rating = agg.get("ratingValue")
        count = agg.get("reviewCount") or agg.get("ratingCount")
        try:
            rating = float(rating) if rating is not None else None
        except (TypeError, ValueError):
            rating = None
        try:
            count = int(count) if count is not None else None
        except (TypeError, ValueError):
            count = None
        return rating, count
    raise NoRecipeDataError("no Recipe JSON-LD block found on page")


def fetch_html(url: str, user_agent: str, timeout: int, retries: int) -> str:
    req_headers = {"User-Agent": user_agent}
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers=req_headers)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            if attempt < retries - 1:
                time.sleep(2**attempt)
    raise last_error  # type: ignore[misc]


def load_checkpoint(path: Path) -> dict[str, dict]:
    """Keyed by url so a resumed run can skip already-fetched recipes."""
    if not path.exists():
        return {}
    try:
        with path.open(encoding="utf-8") as fh:
            entries = json.load(fh)
        return {e["url"]: e for e in entries if e.get("url")}
    except (json.JSONDecodeError, OSError):
        return {}


def save_checkpoint(path: Path, by_url: dict[str, dict]) -> None:
    """Write-to-temp-then-rename so an interrupted write can't corrupt the
    checkpoint (same pattern as scrape.py's save_recipes_to_file)."""
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("w", encoding="utf-8") as fh:
        json.dump(list(by_url.values()), fh, indent=2, ensure_ascii=False)
    temp_path.replace(path)


def cmd_fetch(args: argparse.Namespace) -> int:
    if not args.json.exists():
        print(f"error: {args.json} not found", file=sys.stderr)
        return 1
    with args.json.open(encoding="utf-8") as fh:
        recipes = json.load(fh)

    subset = recipes[args.offset :]
    if args.limit:
        subset = subset[: args.limit]

    by_url = load_checkpoint(args.output)
    pending = [r for r in subset if r.get("url") and r["url"] not in by_url]
    print(
        f"{len(by_url)} already checkpointed, {len(pending)} pending of {len(subset)} in range.",
        file=sys.stderr,
    )

    fetched = 0
    failed = 0
    for i, recipe in enumerate(pending, start=1):
        url = recipe["url"]
        title = recipe.get("title", "")
        try:
            html = fetch_html(url, args.user_agent, args.timeout, args.retries)
            rating, count = extract_rating(html)
            by_url[url] = {
                "url": url,
                "title": title,
                "atk_rating": rating,
                "atk_rating_count": count,
            }
            fetched += 1
            status = f"{rating} ({count} reviews)" if rating is not None else "no rating yet"
            print(f"[{i}/{len(pending)}] {title}: {status}", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001 - log and keep going
            failed += 1
            print(f"[{i}/{len(pending)}] FAILED {title} ({url}): {exc}", file=sys.stderr)

        if fetched and fetched % args.save_interval == 0:
            save_checkpoint(args.output, by_url)

        if i < len(pending):
            time.sleep(args.delay + random.uniform(0, args.jitter))

    save_checkpoint(args.output, by_url)
    print(
        f"\nDone. Fetched {fetched}, failed {failed}. Checkpoint has {len(by_url)} total entries at {args.output}.",
        file=sys.stderr,
    )
    return 0


def sql_str(value) -> str:
    if value is None:
        return "NULL"
    text = str(value)
    return "'" + text.replace("'", "''") + "'"


def build_apply_sql(entries: list[dict], batch_size: int = 0) -> str:
    """UPDATEs matched by title, same non-destructive convention as
    import_atk_recipes.py's build_backfill_image_url_sql: only touches
    unowned catalog rows, only when a rating was actually found.

    With `batch_size == 0` this is one big `BEGIN … COMMIT` (all-or-nothing).
    With `batch_size > 0` the statements are split into per-transaction
    batches that each commit independently — required over the Supabase
    session pooler, where a single ~14.6K-statement transaction is too slow
    to finish before the connection is killed and the whole thing rolls back
    (see import_atk_recipes.py's build_sql for the same fix at import time).
    """
    statements = []
    for entry in entries:
        title = (entry.get("title") or "").strip()
        rating = entry.get("atk_rating")
        if not title or rating is None:
            continue
        # ATK's own JSON-LD occasionally reports a ratingValue outside the
        # 0-5 star scale it otherwise uses everywhere (observed: 5.5 and 6.5
        # on a couple of recipes, each with only a handful of reviews) — a
        # genuine data quality issue on their end, not a parsing bug here.
        # Skip rather than write something that'd render as "6.5" next to a
        # single-star icon.
        if not (0 <= rating <= 5):
            continue
        count = entry.get("atk_rating_count")
        statements.append(
            f"UPDATE recipes SET atk_rating = {rating}, atk_rating_count = "
            f"{count if count is not None else 'NULL'} "
            f"WHERE title = {sql_str(title)} AND user_id IS NULL;"
        )

    step = batch_size if batch_size > 0 else len(statements) or 1
    blocks = []
    for i in range(0, len(statements), step):
        chunk = statements[i : i + step]
        blocks.append("BEGIN;\n" + "\n".join(chunk) + "\nCOMMIT;")
    if not blocks:
        blocks.append("BEGIN;\nCOMMIT;")
    return "\n\n".join(blocks) + "\n"


def cmd_apply(args: argparse.Namespace) -> int:
    if not args.json.exists():
        print(f"error: {args.json} not found", file=sys.stderr)
        return 1
    with args.json.open(encoding="utf-8") as fh:
        entries = json.load(fh)

    rated = [e for e in entries if e.get("atk_rating") is not None]
    sql = build_apply_sql(entries, batch_size=args.batch_size)
    print(f"Prepared to apply ratings for {len(rated)}/{len(entries)} recipes.", file=sys.stderr)

    if args.dry_run:
        sys.stdout.write(sql)
        return 0

    result = subprocess.run(
        ["psql", args.db_url, "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"],
        input=sql,
        text=True,
    )
    if result.returncode != 0:
        print("apply failed (psql exited non-zero)", file=sys.stderr)
        return result.returncode

    print(f"Applied ratings to {args.db_url.split('@')[-1]}.", file=sys.stderr)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subparsers = parser.add_subparsers(dest="command", required=True)

    fetch_parser = subparsers.add_parser("fetch", help="Scrape ATK ratings to a local checkpoint JSON file")
    fetch_parser.add_argument("--json", type=Path, default=DEFAULT_RECIPES_JSON, help="Path to atk_recipes.json (source of title/url pairs)")
    fetch_parser.add_argument("--output", type=Path, default=DEFAULT_RATINGS_JSON, help="Path to the ratings checkpoint JSON file")
    fetch_parser.add_argument("--limit", type=int, default=0, help="Max recipes to fetch this run (0 = all)")
    fetch_parser.add_argument("--offset", type=int, default=0, help="Skip this many recipes from the top")
    fetch_parser.add_argument("--delay", type=float, default=1.0, help="Base delay between requests, in seconds")
    fetch_parser.add_argument("--jitter", type=float, default=0.5, help="Extra random delay (0..jitter) added to each wait")
    fetch_parser.add_argument("--timeout", type=int, default=15, help="Per-request timeout, in seconds")
    fetch_parser.add_argument("--retries", type=int, default=3, help="Retries per URL before giving up")
    fetch_parser.add_argument("--save-interval", type=int, default=20, help="Checkpoint to disk after this many successful fetches")
    fetch_parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT, help="User-Agent header sent with each request")
    fetch_parser.set_defaults(func=cmd_fetch)

    apply_parser = subparsers.add_parser("apply", help="Apply a ratings checkpoint to the recipes table")
    apply_parser.add_argument("--json", type=Path, default=DEFAULT_RATINGS_JSON, help="Path to the ratings checkpoint JSON file")
    apply_parser.add_argument("--db-url", default=DEFAULT_DB_URL, help="Postgres connection string")
    apply_parser.add_argument("--batch-size", type=int, default=0,
                               help="Commit every N UPDATEs in their own transaction (0 = one big transaction). "
                                    "Use for a remote apply over the pooler, where a single huge transaction is too slow to finish.")
    apply_parser.add_argument("--dry-run", action="store_true", help="Print SQL instead of running it")
    apply_parser.set_defaults(func=cmd_apply)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
