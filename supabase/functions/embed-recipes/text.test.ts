// Run: deno test supabase/functions/embed-recipes/text.test.ts
import { buildEmbeddingText } from "./text.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(message ?? `expected ${e}, got ${a}`);
}
function assert(cond: boolean, message: string) {
  if (!cond) throw new Error(message);
}

Deno.test("buildEmbeddingText combines title, tags, and description", () => {
  const text = buildEmbeddingText({
    id: 1,
    title: "Beef Stew",
    description: "A hearty braise for cold nights.",
    recipe_tags: [{ tags: { name: "Dinner" } }, { tags: { name: "Comfort Food" } }],
  });
  assertEquals(text, "Beef Stew. Dinner, Comfort Food. A hearty braise for cold nights.");
});

Deno.test("buildEmbeddingText tolerates missing tags and description", () => {
  assertEquals(buildEmbeddingText({ id: 2, title: "Plain Rice", description: null }), "Plain Rice");
});

Deno.test("buildEmbeddingText skips empty/malformed tag entries", () => {
  const text = buildEmbeddingText({
    id: 3,
    title: "Soup",
    description: "",
    recipe_tags: [{ tags: { name: "" } }, { tags: null }, { tags: { name: "Vegetarian" } }],
  });
  assertEquals(text, "Soup. Vegetarian");
});

Deno.test("buildEmbeddingText caps very long input", () => {
  const text = buildEmbeddingText({ id: 4, title: "X".repeat(2000), description: null });
  assert(text.length <= 1000, `expected <= 1000 chars, got ${text.length}`);
});
