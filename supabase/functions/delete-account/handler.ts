// Pure request-handling logic, split out from index.ts so index.test.ts can
// exercise it without triggering index.ts's module-top-level Deno.serve(...)
// as a side effect — same reasoning as ai-chat's search.ts/index.ts split.

export interface DeleteAccountEnv {
  supabaseUrl?: string;
  publishableKey?: string;
  secretKey?: string;
}

export async function handleDeleteAccount(
  req: Request,
  env: DeleteAccountEnv,
  fetchImpl: typeof fetch = fetch,
): Promise<Response> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json({ error: "Missing Authorization header." }, { status: 401 });
  }

  const { supabaseUrl, publishableKey, secretKey } = env;
  if (!supabaseUrl || !publishableKey || !secretKey) {
    console.error("SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY/SUPABASE_SECRET_KEY are not set for this project.");
    return Response.json({ error: "Account deletion isn't configured yet." }, { status: 500 });
  }

  // Resolve the caller's own user id from their JWT via the Auth API — never
  // trust a client-supplied id, and never decode the JWT ourselves.
  const whoAmI = await fetchImpl(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: publishableKey },
  });
  if (!whoAmI.ok) {
    return Response.json({ error: "Could not verify the signed-in user." }, { status: 401 });
  }
  const { id: userId } = await whoAmI.json() as { id?: string };
  if (!userId) {
    return Response.json({ error: "Could not verify the signed-in user." }, { status: 401 });
  }

  // secretKey (sb_secret_...) is the modern replacement for the legacy
  // service_role JWT — same Admin API access, but individually revocable
  // instead of being tied to the project's shared JWT secret (see
  // DECISIONS.md, 2026-07-14: the legacy secret was being retired).
  const deleteResult = await fetchImpl(`${supabaseUrl}/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${secretKey}`, apikey: secretKey },
  });
  if (!deleteResult.ok) {
    console.error("Failed to delete auth user:", deleteResult.status, await deleteResult.text());
    return Response.json({ error: "Failed to delete account." }, { status: 502 });
  }

  return Response.json({ deleted: true });
}
