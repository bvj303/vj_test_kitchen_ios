// Kitchen Concierge — AI menu-planning chat, backed by Groq (llama-3.3-70b).
//
// Deliberately zero external imports (no npm:/jsr: specifiers) — Deno.serve,
// Deno.env, and fetch are runtime built-ins; ./search.ts is a local relative
// import, not a bundled package, so it doesn't reintroduce the DNS-resolution
// problem this constraint exists for. Auth is handled by the platform's
// default JWT verification (verify_jwt is left at its default `true` in
// config.toml — see supabase/config.toml), so by the time this code runs,
// the caller is already a valid authenticated user. Recipe reads go through
// plain REST calls to PostgREST using the caller's own Authorization header,
// so RLS applies exactly as it does everywhere else in the app (recipes are
// shared-readable by any authenticated user — see DECISIONS.md). No
// service_role/admin access is used here.
import { GroqRequestError, normalizeChatTurns, runGroqWithTools, type ToolLoopResult } from "./search.ts";

// Query embeddings for semantic search are produced by the separate `embed-text`
// function, NOT here: loading the gte-small model in this worker overran the Edge
// Function compute limit and crashed it (WORKER_RESOURCE_LIMIT → 502). ai-chat
// stays light and calls embed-text over HTTP (gated by the shared secret). On any
// failure it returns [] so searchRecipes falls back to keyword search.
function makeEmbedder(supabaseUrl: string, anonKey: string, embedSecret: string | undefined) {
  return async (text: string): Promise<number[]> => {
    if (!embedSecret) return [];
    try {
      const res = await fetch(`${supabaseUrl}/functions/v1/embed-text`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: anonKey, "x-backfill-secret": embedSecret },
        body: JSON.stringify({ text }),
        // Never let a slow embedder hang the whole chat — semantic search is a
        // best-effort enhancement; searchRecipes falls back to keyword on [].
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) return [];
      const data = await res.json();
      return Array.isArray(data?.embedding) ? data.embedding : [];
    } catch (err) {
      console.error("query embed failed:", err);
      return [];
    }
  };
}

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json({ error: "Missing Authorization header." }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid request body." }, { status: 400 });
  }

  // Accepts the full-history `{ messages }` shape or the legacy `{ prompt }`
  // shape, and enforces per-message / whole-conversation size caps (the
  // denial-of-wallet guard against the free-tier quota now that history is sent).
  const messages = normalizeChatTurns(body);
  if (!Array.isArray(messages)) {
    return Response.json({ error: messages.error }, { status: messages.status });
  }

  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) {
    console.error("GROQ_API_KEY is not set for this project.");
    return Response.json(
      { error: "AI planning isn't configured yet — missing GROQ_API_KEY." },
      { status: 500 },
    );
  }

  // Reads the modern APP_PUBLISHABLE_KEY (an explicit Edge Function
  // secret) rather than the legacy auto-injected SUPABASE_ANON_KEY — see
  // DECISIONS.md, 2026-07-14: that legacy key is a JWT signed by the
  // project's legacy JWT secret, which was being retired.
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("APP_PUBLISHABLE_KEY");
  if (!supabaseUrl || !anonKey) {
    console.error("SUPABASE_URL/APP_PUBLISHABLE_KEY are not set for this project.");
    return Response.json({ error: "AI planning isn't configured yet." }, { status: 500 });
  }

  let result: ToolLoopResult;
  try {
    const embed = makeEmbedder(supabaseUrl, anonKey, Deno.env.get("EMBED_BACKFILL_SECRET"));
    result = await runGroqWithTools({ apiKey, messages, authHeader, supabaseUrl, anonKey, embed });
  } catch (err) {
    if (err instanceof GroqRequestError) {
      if (err.status === 408) {
        return Response.json(
          { error: "The assistant took too long to respond — please try again." },
          { status: 504 },
        );
      }
      const status = err.status === 429 ? 429 : 502;
      return Response.json(
        { error: status === 429 ? "The assistant is busy right now — try again shortly." : "Failed to reach the assistant." },
        { status },
      );
    }
    console.error("Network error calling Groq:", err);
    return Response.json({ error: "Failed to reach the assistant." }, { status: 502 });
  }

  if (result.roundCapHit) {
    return Response.json({
      response: "I'm having trouble narrowing that down — could you be a bit more specific about what you're looking for?",
    });
  }

  if (typeof result.text !== "string" || result.text.length === 0) {
    console.error("Unexpected Groq response shape: no text and no tool call.");
    return Response.json({ error: "The assistant returned an empty response." }, { status: 502 });
  }

  // OpenAI/Groq report a truncated reply with finish_reason "length" — flag it
  // rather than returning a silently cut-off plan as if it were complete.
  const response = result.finishReason === "length"
    ? `${result.text}\n\n_(Response was cut short — ask me to continue for the rest.)_`
    : result.text;

  // `recipes` are the ones surfaced by search_recipes this turn; the client
  // renders tappable cards for those the reply actually names.
  return Response.json({ response, recipes: result.recipes });
});
