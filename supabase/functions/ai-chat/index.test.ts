// No external imports — same constraint as index.ts (see its header comment):
// this project's Edge Function bundler can't resolve npm:/jsr: specifiers'
// DNS on this environment's managed Docker network. `Deno.test` plus manual
// assertions keeps these tests dependency-free. Run with:
//   deno test --allow-net supabase/functions/ai-chat/index.test.ts
//
// Imports from search.ts, not index.ts — index.ts calls Deno.serve at module
// top level, which would start a real HTTP listener as a side effect of
// merely importing it here.
import { buildSearchRecipesUrl, clampLimit, escapeIlike, runGeminiWithTools, searchRecipes } from "./search.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new Error(message ?? `expected ${e}, got ${a}`);
  }
}

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("clampLimit defaults to 20 when omitted", () => {
  assertEquals(clampLimit(undefined), 20);
});

Deno.test("clampLimit caps at 25 even when a larger value is requested", () => {
  assertEquals(clampLimit(1000), 25);
});

Deno.test("clampLimit floors at 1 for zero/negative values", () => {
  assertEquals(clampLimit(0), 1);
  assertEquals(clampLimit(-5), 1);
});

Deno.test("escapeIlike escapes percent, underscore, and backslash", () => {
  assertEquals(escapeIlike("100%_done\\"), "100\\%\\_done\\\\");
});

Deno.test("buildSearchRecipesUrl with a query filters by title ilike and orders by id", () => {
  const url = buildSearchRecipesUrl("https://example.supabase.co", { query: "taco" });
  assert(url.includes("title=ilike.*taco*"), `expected title ilike filter, got ${url}`);
  assert(url.includes("order=id"), `expected id order, got ${url}`);
  assert(url.includes("limit=20"), `expected default limit, got ${url}`);
});

Deno.test("buildSearchRecipesUrl with a tag uses an inner-joined embed filter", () => {
  const url = buildSearchRecipesUrl("https://example.supabase.co", { tag: "Vegetarian" });
  assert(url.includes("recipe_tags%21inner"), `expected !inner embed, got ${url}`);
  assert(url.includes("recipe_tags.tags.name=eq.Vegetarian"), `expected tag filter, got ${url}`);
});

Deno.test("buildSearchRecipesUrl with neither query nor tag falls back to most-recent order", () => {
  const url = buildSearchRecipesUrl("https://example.supabase.co", {});
  assert(url.includes("order=id.desc"), `expected most-recent fallback order, got ${url}`);
});

Deno.test("buildSearchRecipesUrl clamps an over-limit request", () => {
  const url = buildSearchRecipesUrl("https://example.supabase.co", { query: "x", limit: 500 });
  assert(url.includes("limit=25"), `expected clamped limit, got ${url}`);
});

Deno.test("searchRecipes maps embedded recipe_tags into a flat tags array", async () => {
  const fetchImpl = (async () =>
    new Response(
      JSON.stringify([
        { id: 1, title: "Tacos", prep_time: 15, servings: 2, recipe_tags: [{ tags: { name: "Mexican" } }] },
      ]),
      { status: 200 },
    )) as typeof fetch;

  const results = await searchRecipes("Bearer token", "https://example.supabase.co", "anon-key", { query: "taco" }, fetchImpl);

  assertEquals(results, [{ id: 1, title: "Tacos", tags: ["Mexican"], prep_time: 15, servings: 2 }]);
});

Deno.test("searchRecipes returns an empty array when the query fails rather than throwing", async () => {
  const fetchImpl = (async () => new Response("boom", { status: 500 })) as typeof fetch;

  const results = await searchRecipes("Bearer token", "https://example.supabase.co", "anon-key", {}, fetchImpl);

  assertEquals(results, []);
});

/// Builds a fake `generateContent` response: a functionCall part if `tag`/`query`
/// aren't done yet, otherwise a plain text reply.
function geminiResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200 });
}

Deno.test("runGeminiWithTools returns Gemini's text directly when it never calls the tool", async () => {
  const fetchImpl = (async () =>
    geminiResponse({ candidates: [{ content: { parts: [{ text: "Try the Carbonara." }] }, finishReason: "STOP" }] })) as typeof fetch;

  const result = await runGeminiWithTools({
    apiKey: "key",
    userPrompt: "what should I make?",
    authHeader: "Bearer token",
    supabaseUrl: "https://example.supabase.co",
    anonKey: "anon-key",
    fetchImpl,
  });

  assertEquals(result, { text: "Try the Carbonara.", finishReason: "STOP", blocked: false, roundCapHit: false, recipes: [] });
});

Deno.test("runGeminiWithTools executes a tool call and feeds the result back for a final answer", async () => {
  let call = 0;
  const fetchImpl = (async (url: string | URL, init?: RequestInit) => {
    call += 1;
    if (typeof url === "string" && url.includes("generativelanguage.googleapis.com")) {
      if (call === 1) {
        return geminiResponse({
          candidates: [{ content: { parts: [{ functionCall: { name: "search_recipes", args: { query: "taco" } } }] } }],
        });
      }
      return geminiResponse({
        candidates: [{ content: { parts: [{ text: "The Beef Tacos recipe fits." }] }, finishReason: "STOP" }],
      });
    }
    // The search_recipes PostgREST call.
    return new Response(JSON.stringify([{ id: 2, title: "Beef Tacos", prep_time: 20, servings: 4, recipe_tags: [] }]), { status: 200 });
  }) as typeof fetch;

  const result = await runGeminiWithTools({
    apiKey: "key",
    userPrompt: "I want tacos",
    authHeader: "Bearer token",
    supabaseUrl: "https://example.supabase.co",
    anonKey: "anon-key",
    fetchImpl,
  });

  assertEquals(result.text, "The Beef Tacos recipe fits.");
  assertEquals(result.roundCapHit, false);
  // Recipes surfaced by the tool are returned for the client to render as cards.
  assertEquals(result.recipes, [{ id: 2, title: "Beef Tacos" }]);
});

Deno.test("runGeminiWithTools stops after MAX_TOOL_ROUNDS and reports roundCapHit instead of looping forever", async () => {
  const fetchImpl = (async (url: string | URL) => {
    if (typeof url === "string" && url.includes("generativelanguage.googleapis.com")) {
      // Always asks for another search — never produces a final answer.
      return geminiResponse({
        candidates: [{ content: { parts: [{ functionCall: { name: "search_recipes", args: { query: "anything" } } }] } }],
      });
    }
    return new Response(JSON.stringify([]), { status: 200 });
  }) as typeof fetch;

  const result = await runGeminiWithTools({
    apiKey: "key",
    userPrompt: "keep searching forever",
    authHeader: "Bearer token",
    supabaseUrl: "https://example.supabase.co",
    anonKey: "anon-key",
    fetchImpl,
  });

  assertEquals(result.roundCapHit, true);
  assertEquals(result.text, undefined);
});
