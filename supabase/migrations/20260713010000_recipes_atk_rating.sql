-- America's Test Kitchen's own average rating + review count for a recipe,
-- scraped from the public (unauthenticated) recipe page's Recipe JSON-LD
-- (`aggregateRating.ratingValue`/`reviewCount`) — see scripts/scrape_atk_ratings.py.
-- Distinct from recipe_ratings (household members' own ratings): this is a
-- read-only external data point, not something the app writes from user input.
alter table public.recipes add column if not exists atk_rating numeric(3, 2);
alter table public.recipes add column if not exists atk_rating_count integer;
