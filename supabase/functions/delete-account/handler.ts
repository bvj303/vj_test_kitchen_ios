// Pure request-handling logic, split out from index.ts so index.test.ts can
// exercise it without triggering index.ts's module-top-level Deno.serve(...)
// as a side effect — same reasoning as ai-chat's search.ts/index.ts split.

export interface DeleteAccountEnv {
  supabaseUrl?: string;
  anonKey?: string;
  serviceRoleKey?: string;
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

  const { supabaseUrl, anonKey, serviceRoleKey } = env;
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("SUPABASE_URL/SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY are not set for this project.");
    return Response.json({ error: "Account deletion isn't configured yet." }, { status: 500 });
  }

  // Resolve the caller's own user id from their JWT via the Auth API — never
  // trust a client-supplied id, and never decode the JWT ourselves.
  const whoAmI = await fetchImpl(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: anonKey },
  });
  if (!whoAmI.ok) {
    return Response.json({ error: "Could not verify the signed-in user." }, { status: 401 });
  }
  const { id: userId } = await whoAmI.json() as { id?: string };
  if (!userId) {
    return Response.json({ error: "Could not verify the signed-in user." }, { status: 401 });
  }

  const deleteResult = await fetchImpl(`${supabaseUrl}/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${serviceRoleKey}`, apikey: serviceRoleKey },
  });
  if (!deleteResult.ok) {
    console.error("Failed to delete auth user:", deleteResult.status, await deleteResult.text());
    return Response.json({ error: "Failed to delete account." }, { status: 502 });
  }

  return Response.json({ deleted: true });
}
