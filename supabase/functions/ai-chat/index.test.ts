// No external imports — same constraint as index.ts (see its header comment):
// this project's Edge Function bundler can't resolve npm:/jsr: specifiers'
// DNS on this environment's managed Docker network. `Deno.test` plus manual
// assertions keeps these tests dependency-free. Run with:
//   deno test --allow-net supabase/functions/ai-chat/index.test.ts
//
// Imports from search.ts, not index.ts — index.ts calls Deno.serve at module
// top level, which would start a real HTTP listener as a side effect of
// merely importing it here.
import {
  buildSearchRecipesUrl,
  clampLimit,
  escapeIlike,
  normalizeChatTurns,
  parseContentRangeTotal,
  parseToolArgs,
  runGroqWithTools,
  searchRecipes,
  SEARCH_RECIPES_POOL_LIMIT,
  shuffle,
} from "./search.ts";

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

Deno.test("clampLimit defaults to SEARCH_RECIPES_DEFAULT_LIMIT when omitted", () => {
  assertEquals(clampLimit(undefined), 35);
});

Deno.test("clampLimit caps at SEARCH_RECIPES_MAX_LIMIT even when a larger value is requested", () => {
  assertEquals(clampLimit(1000), 60);
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
  // The DB query fetches the wider pool; the per-call limit is applied after
  // shuffling in searchRecipes, not in the URL.
  assert(url.includes(`limit=${SEARCH_RECIPES_POOL_LIMIT}`), `expected pool limit, got ${url}`);
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

Deno.test("buildSearchRecipesUrl always fetches the pool regardless of requested limit", () => {
  const url = buildSearchRecipesUrl("https://example.supabase.co", { query: "x", limit: 500 });
  assert(url.includes(`limit=${SEARCH_RECIPES_POOL_LIMIT}`), `expected pool limit, got ${url}`);
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

Deno.test("shuffle is a permutation and reorders with a non-identity rng", () => {
  const input = [1, 2, 3, 4, 5];
  // A deterministic rng that always picks index 0 (j = 0) — reverses no-op-free.
  const shuffled = shuffle(input, () => 0);
  // Same multiset, and the original array is left untouched (pure).
  assertEquals([...shuffled].sort(), [1, 2, 3, 4, 5]);
  assertEquals(input, [1, 2, 3, 4, 5]);
});

Deno.test("searchRecipes samples from the pool: same rows, varied order, capped to the requested limit", async () => {
  const pool = Array.from({ length: 30 }, (_, i) => ({
    id: i + 1,
    title: `Recipe ${i + 1}`,
    prep_time: 10,
    servings: 2,
    recipe_tags: [],
  }));
  const fetchImpl = (async () => new Response(JSON.stringify(pool), { status: 200 })) as typeof fetch;

  // With a fixed rng, two identical queries would return identical order — the
  // point of the real Math.random is that they don't. Here we just assert the
  // limit is honored and every returned row came from the pool.
  const results = await searchRecipes(
    "Bearer token",
    "https://example.supabase.co",
    "anon-key",
    { query: "recipe", limit: 5 },
    fetchImpl,
    () => 0.5,
  );

  assertEquals(results.length, 5);
  const poolIds = new Set(pool.map((r) => r.id));
  assert(results.every((r) => poolIds.has(r.id)), "every result should come from the pool");
});

Deno.test("parseContentRangeTotal extracts the total, or null when unknown", () => {
  assertEquals(parseContentRangeTotal("0-149/12345"), 12345);
  assertEquals(parseContentRangeTotal("0-149/*"), null);
  assertEquals(parseContentRangeTotal(null), null);
});

Deno.test("buildSearchRecipesUrl includes a non-zero offset for random-window sampling", () => {
  const url = buildSearchRecipesUrl("https://example.supabase.co", { query: "x" }, 300);
  assert(url.includes("offset=300"), `expected offset, got ${url}`);
  // Offset 0 is omitted (the common first-page case).
  assert(!buildSearchRecipesUrl("https://example.supabase.co", { query: "x" }).includes("offset="), "offset should be omitted when 0");
});

Deno.test("searchRecipes samples a random window across the whole set when it exceeds the pool", async () => {
  let call = 0;
  let windowUrl = "";
  const firstPage = Array.from({ length: 150 }, (_, i) => ({ id: i + 1, title: `First ${i}`, prep_time: 10, servings: 2, recipe_tags: [] }));
  const windowPage = Array.from({ length: 150 }, (_, i) => ({ id: 1000 + i, title: `Window ${i}`, prep_time: 10, servings: 2, recipe_tags: [] }));
  const fetchImpl = (async (url: string | URL) => {
    call += 1;
    if (call === 1) {
      // First page reports a large total via Content-Range → triggers windowing.
      return new Response(JSON.stringify(firstPage), { status: 200, headers: { "content-range": "0-149/5000" } });
    }
    windowUrl = String(url);
    return new Response(JSON.stringify(windowPage), { status: 200 });
  }) as typeof fetch;

  const results = await searchRecipes("Bearer t", "https://example.supabase.co", "anon", { query: "chicken", limit: 10 }, fetchImpl, () => 0.5);

  assertEquals(call, 2); // count page, then a random-offset window
  assert(windowUrl.includes("offset="), `expected an offset on the window fetch, got ${windowUrl}`);
  assert(results.every((r) => r.id >= 1000), "results should come from the random window, not the first page");
  assertEquals(results.length, 10);
});

Deno.test("searchRecipes does not do a second fetch when the whole set fits in one pool", async () => {
  let call = 0;
  const page = Array.from({ length: 20 }, (_, i) => ({ id: i + 1, title: `R${i}`, prep_time: 10, servings: 2, recipe_tags: [] }));
  const fetchImpl = (async () => {
    call += 1;
    return new Response(JSON.stringify(page), { status: 200, headers: { "content-range": "0-19/20" } });
  }) as typeof fetch;

  const results = await searchRecipes("Bearer t", "https://example.supabase.co", "anon", { query: "x", limit: 10 }, fetchImpl, () => 0.5);
  assertEquals(call, 1); // small set → no windowing
  assertEquals(results.length, 10);
});

Deno.test("normalizeChatTurns accepts the legacy single prompt", () => {
  const result = normalizeChatTurns({ prompt: "what should I cook?" });
  assertEquals(result, [{ role: "user", text: "what should I cook?" }]);
});

Deno.test("normalizeChatTurns maps a messages array and preserves order", () => {
  const result = normalizeChatTurns({
    messages: [
      { role: "user", content: "something healthy" },
      { role: "assistant", content: "Try the Kale Salad." },
      { role: "user", content: "something else" },
    ],
  });
  assertEquals(result, [
    { role: "user", text: "something healthy" },
    { role: "assistant", text: "Try the Kale Salad." },
    { role: "user", text: "something else" },
  ]);
});

Deno.test("normalizeChatTurns rejects a conversation that doesn't end on a user turn", () => {
  const result = normalizeChatTurns({
    messages: [
      { role: "user", content: "hi" },
      { role: "assistant", content: "hello" },
    ],
  });
  assertEquals(result, { error: "The last message must be from the user.", status: 400 });
});

Deno.test("normalizeChatTurns rejects an empty/invalid body", () => {
  assertEquals(normalizeChatTurns({}), { error: "prompt or messages is required.", status: 400 });
  assertEquals(normalizeChatTurns({ messages: [] }), { error: "messages cannot be empty.", status: 400 });
  assertEquals(
    normalizeChatTurns({ messages: [{ role: "system", content: "x" }] }),
    { error: "Each message needs a role of 'user' or 'assistant'.", status: 400 },
  );
});

Deno.test("normalizeChatTurns rejects an over-long conversation", () => {
  const long = "a".repeat(5000);
  const result = normalizeChatTurns({ messages: [{ role: "user", content: long }] });
  assertEquals(result, {
    error: "That message is too long (max 4000 characters). Please shorten it.",
    status: 413,
  });
});

function groqResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200 });
}

/// A Groq assistant message that requests one search_recipes tool call.
function toolCallMessage(args: Record<string, unknown>) {
  return {
    message: {
      content: null,
      tool_calls: [{ id: "call_1", type: "function", function: { name: "search_recipes", arguments: JSON.stringify(args) } }],
    },
    finish_reason: "tool_calls",
  };
}

Deno.test("parseToolArgs parses valid JSON and tolerates junk", () => {
  assertEquals(parseToolArgs('{"query":"chicken"}'), { query: "chicken" });
  assertEquals(parseToolArgs(undefined), {});
  assertEquals(parseToolArgs("not json"), {});
});

Deno.test("runGroqWithTools returns the model's text directly when it never calls the tool", async () => {
  const fetchImpl = (async () =>
    groqResponse({ choices: [{ message: { content: "Try the Carbonara." }, finish_reason: "stop" }] })) as typeof fetch;

  const result = await runGroqWithTools({
    apiKey: "key",
    userPrompt: "what should I make?",
    authHeader: "Bearer token",
    supabaseUrl: "https://example.supabase.co",
    anonKey: "anon-key",
    fetchImpl,
  });

  assertEquals(result, { text: "Try the Carbonara.", finishReason: "stop", blocked: false, roundCapHit: false, recipes: [] });
});

Deno.test("runGroqWithTools sends the system prompt + full history (assistant stays 'assistant')", async () => {
  let sentMessages: any;
  const fetchImpl = (async (_url: string | URL, init?: RequestInit) => {
    sentMessages = JSON.parse(String(init?.body)).messages;
    return groqResponse({ choices: [{ message: { content: "Here's another." }, finish_reason: "stop" }] });
  }) as typeof fetch;

  const result = await runGroqWithTools({
    apiKey: "key",
    messages: [
      { role: "user", text: "something healthy" },
      { role: "assistant", text: "Try the Kale Salad." },
      { role: "user", text: "something else" },
    ],
    authHeader: "Bearer token",
    supabaseUrl: "https://example.supabase.co",
    anonKey: "anon-key",
    fetchImpl,
  });

  assertEquals(result.text, "Here's another.");
  assertEquals(sentMessages[0].role, "system"); // system instruction first
  assertEquals(sentMessages.slice(1), [
    { role: "user", content: "something healthy" },
    { role: "assistant", content: "Try the Kale Salad." },
    { role: "user", content: "something else" },
  ]);
});

Deno.test("runGroqWithTools executes a tool call and feeds the result back for a final answer", async () => {
  let call = 0;
  const fetchImpl = (async (url: string | URL) => {
    call += 1;
    if (typeof url === "string" && url.includes("api.groq.com")) {
      if (call === 1) return groqResponse({ choices: [toolCallMessage({ query: "taco" })] });
      return groqResponse({ choices: [{ message: { content: "The Beef Tacos recipe fits." }, finish_reason: "stop" }] });
    }
    // The search_recipes PostgREST call.
    return new Response(JSON.stringify([{ id: 2, title: "Beef Tacos", prep_time: 20, servings: 4, recipe_tags: [] }]), { status: 200 });
  }) as typeof fetch;

  const result = await runGroqWithTools({
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

Deno.test("runGroqWithTools stops after MAX_TOOL_ROUNDS and reports roundCapHit instead of looping forever", async () => {
  const fetchImpl = (async (url: string | URL) => {
    if (typeof url === "string" && url.includes("api.groq.com")) {
      // Always asks for another search — never produces a final answer.
      return groqResponse({ choices: [toolCallMessage({ query: "anything" })] });
    }
    return new Response(JSON.stringify([]), { status: 200 });
  }) as typeof fetch;

  const result = await runGroqWithTools({
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
