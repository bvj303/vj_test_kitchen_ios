// Kitchen Concierge — AI menu-planning chat, backed by Gemini.
//
// Deliberately zero external imports (no npm:/jsr: specifiers) — Deno.serve,
// Deno.env, and fetch are runtime built-ins. Auth is handled by the
// platform's default JWT verification (verify_jwt is left at its default
// `true` in config.toml — see supabase/config.toml), so by the time this
// code runs, the caller is already a valid authenticated user. Recipe reads
// go through plain REST calls to PostgREST using the caller's own
// Authorization header, so RLS applies exactly as it does everywhere else
// in the app (recipes are shared-readable by any authenticated user — see
// DECISIONS.md). No service_role/admin access is used here.
const GEMINI_MODEL = "gemini-3.1-flash-lite";

interface RecipeCatalogEntry {
  id: number;
  title: string;
  tags: string[];
  prep_time: number | null;
  servings: number | null;
}

const CATALOG_PAGE_SIZE = 1000;

async function loadRecipeCatalog(authHeader: string): Promise<RecipeCatalogEntry[]> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return [];

  const catalog: RecipeCatalogEntry[] = [];
  // Paginate so the catalog isn't silently truncated at PostgREST's default
  // max-rows cap once the recipe count grows (Stage 8 import).
  for (let offset = 0; ; offset += CATALOG_PAGE_SIZE) {
    const url = `${supabaseUrl}/rest/v1/recipes?select=id,title,prep_time,servings,recipe_tags(tags(name))&order=id&limit=${CATALOG_PAGE_SIZE}&offset=${offset}`;
    const res = await fetch(url, {
      headers: { apikey: anonKey, Authorization: authHeader },
    });

    if (!res.ok) {
      console.error("Failed to load recipe catalog:", res.status, await res.text());
      return catalog;
    }

    const rows = await res.json();
    for (const r of rows) {
      catalog.push({
        id: r.id,
        title: r.title,
        tags: (r.recipe_tags ?? [])
          .map((rt: any) => rt.tags?.name)
          .filter((name: unknown): name is string => typeof name === "string"),
        prep_time: r.prep_time,
        servings: r.servings,
      });
    }

    if (rows.length < CATALOG_PAGE_SIZE) break;
  }

  return catalog;
}

function buildSystemInstruction(catalogJson: string): string {
  return `You are "Kitchen Concierge," a friendly, concise meal-planning assistant inside the VJ Test Kitchen app.

You have the user's full recipe collection below as a compact JSON catalog (id, title, tags, prep_time in minutes, servings). When recommending a meal plan or a specific dish, prefer recipes from this catalog when they genuinely fit, and refer to them by their exact title. If nothing in the catalog fits what the user asked for, say so plainly and suggest a general idea instead of inventing a fake recipe.

Keep responses conversational and concise. Use simple markdown — short paragraphs, bullet lists for multi-day plans.

Recipe catalog:
${catalogJson}`;
}

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json({ error: "Missing Authorization header." }, { status: 401 });
  }

  let prompt: unknown;
  try {
    ({ prompt } = await req.json());
  } catch {
    return Response.json({ error: "Invalid request body." }, { status: 400 });
  }

  if (typeof prompt !== "string" || prompt.trim().length === 0) {
    return Response.json({ error: "prompt is required." }, { status: 400 });
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("GEMINI_API_KEY is not set for this project.");
    return Response.json(
      { error: "AI planning isn't configured yet — missing GEMINI_API_KEY." },
      { status: 500 },
    );
  }

  const catalog = await loadRecipeCatalog(authHeader);
  const systemInstruction = buildSystemInstruction(JSON.stringify(catalog));

  let geminiResponse: Response;
  try {
    geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemInstruction }] },
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 2048,
          },
        }),
      },
    );
  } catch (err) {
    console.error("Network error calling Gemini:", err);
    return Response.json({ error: "Failed to reach Gemini." }, { status: 502 });
  }

  if (!geminiResponse.ok) {
    const errText = await geminiResponse.text();
    console.error("Gemini API error:", geminiResponse.status, errText);
    const status = geminiResponse.status === 429 ? 429 : 502;
    return Response.json(
      { error: status === 429 ? "Gemini rate limit reached — try again shortly." : "Failed to reach Gemini." },
      { status },
    );
  }

  const geminiData = await geminiResponse.json();
  const candidate = geminiData?.candidates?.[0];
  const finishReason = candidate?.finishReason;
  const text = candidate?.content?.parts?.[0]?.text;

  // A blocked prompt yields no candidate / a SAFETY finish reason with no text.
  // Return it as a normal assistant reply (the client decodes `response`, not
  // `error`, on 2xx) so the concierge simply declines in-chat.
  if (typeof text !== "string" || text.length === 0) {
    if (finishReason === "SAFETY" || geminiData?.promptFeedback?.blockReason) {
      return Response.json({
        response: "I can't help with that particular request — try rephrasing your meal or recipe question.",
      });
    }
    console.error("Unexpected Gemini response shape:", JSON.stringify(geminiData));
    return Response.json({ error: "Gemini returned an empty response." }, { status: 502 });
  }

  // MAX_TOKENS means the reply was cut off mid-sentence — flag it rather than
  // returning a silently truncated plan as if it were complete.
  const response = finishReason === "MAX_TOKENS"
    ? `${text}\n\n_(Response was cut short — ask me to continue for the rest.)_`
    : text;

  return Response.json({ response });
});
