// embed-text — returns a gte-small embedding for a single piece of text.
//
// Exists so the ai-chat concierge can get a QUERY embedding without loading the
// (memory/CPU-heavy) gte-small model into its own worker — doing that in ai-chat
// overran the Edge Function compute limit and crashed the worker (a 502 to the
// client). This function loads the model and embeds exactly one string per call,
// which stays comfortably within limits; ai-chat calls it over HTTP.
//
// Zero external imports; `Supabase.ai` is an Edge Runtime built-in. Operational/
// internal endpoint gated by a shared secret (EMBED_BACKFILL_SECRET), so
// verify_jwt is false for this function in config.toml.
declare const Supabase: { ai: { Session: new (model: string) => { run(input: string, opts?: { mean_pool?: boolean; normalize?: boolean }): Promise<number[]> } } };

let session: { run(input: string, opts?: { mean_pool?: boolean; normalize?: boolean }): Promise<number[]> } | undefined;

Deno.serve(async (req: Request) => {
  const secret = Deno.env.get("EMBED_BACKFILL_SECRET");
  const provided = req.headers.get("x-backfill-secret") ?? req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!secret || provided !== secret) {
    return Response.json({ error: "Unauthorized." }, { status: 401 });
  }

  let body: { text?: unknown };
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid body." }, { status: 400 });
  }
  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (!text) {
    return Response.json({ error: "text is required." }, { status: 400 });
  }

  try {
    session ??= new Supabase.ai.Session("gte-small");
    const embedding = await session.run(text.slice(0, 1000), { mean_pool: true, normalize: true });
    return Response.json({ embedding });
  } catch (err) {
    console.error("embed-text failed:", err);
    return Response.json({ error: "Embedding failed." }, { status: 500 });
  }
});
