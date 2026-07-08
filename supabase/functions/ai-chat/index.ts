// Kitchen Concierge — AI menu-planning chat, backed by Gemini.
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
import { GeminiRequestError, normalizeChatTurns, runGeminiWithTools, type ToolLoopResult } from "./search.ts";

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
  // denial-of-wallet guard against the Gemini quota now that history is sent).
  const messages = normalizeChatTurns(body);
  if (!Array.isArray(messages)) {
    return Response.json({ error: messages.error }, { status: messages.status });
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("GEMINI_API_KEY is not set for this project.");
    return Response.json(
      { error: "AI planning isn't configured yet — missing GEMINI_API_KEY." },
      { status: 500 },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    console.error("SUPABASE_URL/SUPABASE_ANON_KEY are not set for this project.");
    return Response.json({ error: "AI planning isn't configured yet." }, { status: 500 });
  }

  let result: ToolLoopResult;
  try {
    result = await runGeminiWithTools({ apiKey, messages, authHeader, supabaseUrl, anonKey });
  } catch (err) {
    if (err instanceof GeminiRequestError) {
      const status = err.status === 429 ? 429 : 502;
      return Response.json(
        { error: status === 429 ? "Gemini rate limit reached — try again shortly." : "Failed to reach Gemini." },
        { status },
      );
    }
    console.error("Network error calling Gemini:", err);
    return Response.json({ error: "Failed to reach Gemini." }, { status: 502 });
  }

  if (result.roundCapHit) {
    return Response.json({
      response: "I'm having trouble narrowing that down — could you be a bit more specific about what you're looking for?",
    });
  }

  // A blocked prompt yields no candidate / a SAFETY finish reason with no text.
  // Return it as a normal assistant reply (the client decodes `response`, not
  // `error`, on 2xx) so the concierge simply declines in-chat.
  if (typeof result.text !== "string" || result.text.length === 0) {
    if (result.blocked) {
      return Response.json({
        response: "I can't help with that particular request — try rephrasing your meal or recipe question.",
      });
    }
    console.error("Unexpected Gemini response shape: no text and no function call.");
    return Response.json({ error: "Gemini returned an empty response." }, { status: 502 });
  }

  // MAX_TOKENS means the reply was cut off mid-sentence — flag it rather than
  // returning a silently truncated plan as if it were complete.
  const response = result.finishReason === "MAX_TOKENS"
    ? `${result.text}\n\n_(Response was cut short — ask me to continue for the rest.)_`
    : result.text;

  // `recipes` are the ones surfaced by search_recipes this turn; the client
  // renders tappable cards for those the reply actually names.
  return Response.json({ response, recipes: result.recipes });
});
