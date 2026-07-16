// embed-recipes — one-time / re-runnable backfill that generates a gte-small
// embedding for every recipe missing one, so the concierge can do semantic
// search (see the recipe_embeddings migration + ai-chat/search.ts).
//
// Zero external imports (same constraint as ai-chat/delete-account): Deno.serve,
// Deno.env, fetch, and the `Supabase.ai` global (Edge Runtime built-in) only;
// ./text.ts is a local relative import.
//
// Operational endpoint, not user-facing: gated by a shared secret
// (EMBED_BACKFILL_SECRET) rather than a user JWT, so verify_jwt is set to false
// for this function in config.toml. DB writes use the service key
// (APP_SECRET_KEY) so it can update the shared (unowned) catalog rows, which RLS
// would otherwise block. Idempotent: only touches rows where embedding is null,
// so it's safe to call repeatedly (and to add new recipes later, then re-run).
import { buildEmbeddingText, type RecipeToEmbed } from "./text.ts";

// Deno / Supabase Edge Runtime provides `Supabase.ai` as a global; declare it so
// this type-checks under plain `deno check` too.
declare const Supabase: { ai: { Session: new (model: string) => { run(input: string, opts?: { mean_pool?: boolean; normalize?: boolean }): Promise<number[]> } } };

const DEFAULT_BATCH = 100;

Deno.serve(async (req: Request) => {
  const secret = Deno.env.get("EMBED_BACKFILL_SECRET");
  if (!secret) {
    console.error("EMBED_BACKFILL_SECRET is not set.");
    return Response.json({ error: "Backfill isn't configured." }, { status: 500 });
  }
  // Gate: the caller must present the shared secret (verify_jwt is off for this fn).
  const provided = req.headers.get("x-backfill-secret") ?? req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (provided !== secret) {
    return Response.json({ error: "Unauthorized." }, { status: 401 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("APP_SECRET_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("SUPABASE_URL / APP_SECRET_KEY not set.");
    return Response.json({ error: "Backfill isn't configured." }, { status: 500 });
  }

  const url = new URL(req.url);
  const batch = Math.min(Math.max(Number(url.searchParams.get("batch")) || DEFAULT_BATCH, 1), 250);

  const admin = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" };

  // Pull a batch of recipes still missing an embedding, with their tags.
  const listRes = await fetch(
    `${supabaseUrl}/rest/v1/recipes?select=id,title,description,recipe_tags(tags(name))&embedding=is.null&limit=${batch}`,
    { headers: admin },
  );
  if (!listRes.ok) {
    console.error("list recipes failed:", listRes.status, await listRes.text());
    return Response.json({ error: "Failed to list recipes." }, { status: 502 });
  }
  const recipes: RecipeToEmbed[] = await listRes.json();

  if (recipes.length === 0) {
    return Response.json({ processed: 0, remaining: 0, done: true });
  }

  const session = new Supabase.ai.Session("gte-small");

  // Embed + write each recipe. Embeddings run sequentially (the model session is
  // fast and shared); the DB writes go out concurrently.
  let processed = 0;
  const writes: Promise<Response>[] = [];
  for (const recipe of recipes) {
    const text = buildEmbeddingText(recipe);
    const embedding = await session.run(text, { mean_pool: true, normalize: true });
    writes.push(fetch(`${supabaseUrl}/rest/v1/recipes?id=eq.${recipe.id}`, {
      method: "PATCH",
      headers: admin,
      body: JSON.stringify({ embedding }),
    }));
    processed += 1;
  }

  const results = await Promise.all(writes);
  const failed = results.filter((r) => !r.ok).length;
  if (failed > 0) console.error(`${failed}/${processed} embedding writes failed in this batch.`);

  // How many still need embedding (so a driver loop knows when to stop).
  const countRes = await fetch(
    `${supabaseUrl}/rest/v1/recipes?select=id&embedding=is.null&limit=1`,
    { headers: { ...admin, Prefer: "count=exact" } },
  );
  const remaining = Number((countRes.headers.get("content-range") ?? "*/0").split("/")[1]) || 0;

  return Response.json({ processed, failed, remaining, done: remaining === 0 });
});
