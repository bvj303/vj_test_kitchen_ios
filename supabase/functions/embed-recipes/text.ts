// Pure helpers for the embed-recipes backfill, split from index.ts (which calls
// Deno.serve at module top level) so they're unit-testable.

export interface RecipeToEmbed {
  id: number;
  title: string | null;
  description: string | null;
  recipe_tags?: { tags?: { name?: string } | null }[] | null;
}

/// Builds the text fed to the embedding model for one recipe. Combines the
/// title, its tags (course/cuisine/traits), and description — the fields that
/// carry the recipe's searchable *meaning* — so a query like "cozy winter
/// dinner" matches stews/soups even without those exact words. Title is repeated
/// implicitly by leading with it. Kept compact (gte-small truncates long input).
export function buildEmbeddingText(recipe: RecipeToEmbed): string {
  const parts: string[] = [];
  const title = (recipe.title ?? "").trim();
  if (title) parts.push(title);

  const tags = (recipe.recipe_tags ?? [])
    .map((rt) => rt?.tags?.name)
    .filter((n): n is string => typeof n === "string" && n.trim().length > 0);
  if (tags.length) parts.push(tags.join(", "));

  const description = (recipe.description ?? "").trim();
  if (description) parts.push(description);

  // Fall back to the title alone (or an empty string) so we never embed nothing.
  return parts.join(". ").slice(0, 1000);
}
