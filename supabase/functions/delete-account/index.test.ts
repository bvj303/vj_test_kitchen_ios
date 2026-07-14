// No external imports — same constraint as index.ts (see its header comment).
// Run with:
//   deno test --allow-net supabase/functions/delete-account/index.test.ts
//
// Imports from handler.ts, not index.ts — index.ts calls Deno.serve at
// module top level, which would start a real HTTP listener as a side effect
// of merely importing it here.
import { handleDeleteAccount } from "./handler.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new Error(message ?? `expected ${e}, got ${a}`);
  }
}

const env = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  secretKey: "secret-key",
};

Deno.test("handleDeleteAccount rejects a request with no Authorization header", async () => {
  const response = await handleDeleteAccount(new Request("https://x/delete-account"), env);
  assertEquals(response.status, 401);
});

Deno.test("handleDeleteAccount returns 500 when required env vars are missing", async () => {
  const req = new Request("https://x/delete-account", { headers: { Authorization: "Bearer token" } });
  const response = await handleDeleteAccount(req, {});
  assertEquals(response.status, 500);
});

Deno.test("handleDeleteAccount returns 401 when the Auth API can't resolve the caller", async () => {
  const fetchImpl = (async () => new Response("unauthorized", { status: 401 })) as typeof fetch;
  const req = new Request("https://x/delete-account", { headers: { Authorization: "Bearer bad-token" } });

  const response = await handleDeleteAccount(req, env, fetchImpl);

  assertEquals(response.status, 401);
});

Deno.test("handleDeleteAccount returns 502 when the admin delete call fails", async () => {
  const fetchImpl = (async (url: string | URL) => {
    if (typeof url === "string" && url.endsWith("/auth/v1/user")) {
      return new Response(JSON.stringify({ id: "user-123" }), { status: 200 });
    }
    return new Response("boom", { status: 500 });
  }) as typeof fetch;
  const req = new Request("https://x/delete-account", { headers: { Authorization: "Bearer token" } });

  const response = await handleDeleteAccount(req, env, fetchImpl);

  assertEquals(response.status, 502);
});

Deno.test("handleDeleteAccount deletes the caller's own user id via the Admin API and reports success", async () => {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchImpl = (async (url: string | URL, init?: RequestInit) => {
    calls.push({ url: url.toString(), init });
    if (url.toString().endsWith("/auth/v1/user")) {
      return new Response(JSON.stringify({ id: "user-123" }), { status: 200 });
    }
    return new Response(JSON.stringify({}), { status: 200 });
  }) as typeof fetch;
  const req = new Request("https://x/delete-account", { headers: { Authorization: "Bearer token" } });

  const response = await handleDeleteAccount(req, env, fetchImpl);

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: true });

  const adminCall = calls.find((c) => c.url.includes("/auth/v1/admin/users/"));
  assertEquals(adminCall?.url, "https://example.supabase.co/auth/v1/admin/users/user-123");
  assertEquals(adminCall?.init?.method, "DELETE");
  assertEquals((adminCall?.init?.headers as Record<string, string>)?.Authorization, "Bearer secret-key");
});
