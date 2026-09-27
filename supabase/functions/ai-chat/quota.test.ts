// Per-user rate limit for the Kitchen Concierge (the free Groq tier is shared
// by the whole household — one runaway client must not burn everyone's daily
// quota). Dependency-free like index.test.ts. Run with:
//   deno test --allow-net supabase/functions/ai-chat/quota.test.ts
import {
  AI_CHAT_DAILY_LIMIT,
  AI_CHAT_HOURLY_LIMIT,
  consumeChatQuota,
  quotaExceededMessage,
} from "./quota.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(message ?? `expected ${e}, got ${a}`);
}
function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("consumeChatQuota calls the RPC as the caller (RLS identity) with the configured limits", async () => {
  let url = "";
  let init: RequestInit | undefined;
  const fetchImpl = (async (u: string | URL, i?: RequestInit) => {
    url = String(u);
    init = i;
    return new Response(JSON.stringify({ allowed: true, retry_after_seconds: 0 }), { status: 200 });
  }) as typeof fetch;

  const result = await consumeChatQuota("Bearer user-jwt", "https://x.supabase.co", "pub-key", fetchImpl);

  assertEquals(result, { allowed: true });
  assertEquals(url, "https://x.supabase.co/rest/v1/rpc/consume_ai_chat_quota");
  const headers = init?.headers as Record<string, string>;
  assertEquals(headers.Authorization, "Bearer user-jwt"); // the caller's token, never a service key
  assertEquals(headers.apikey, "pub-key");
  assertEquals(JSON.parse(String(init?.body)), { p_hourly_limit: AI_CHAT_HOURLY_LIMIT, p_daily_limit: AI_CHAT_DAILY_LIMIT });
});

Deno.test("consumeChatQuota reports a denial with its retry-after", async () => {
  const fetchImpl = (async () =>
    new Response(JSON.stringify({ allowed: false, retry_after_seconds: 1260 }), { status: 200 })) as typeof fetch;
  assertEquals(await consumeChatQuota("Bearer t", "https://x", "k", fetchImpl), { allowed: false, retryAfterSeconds: 1260 });
});

Deno.test("consumeChatQuota fails OPEN (flagged) when the check itself breaks — a quota outage must not take the concierge down", async () => {
  const errored = (async () => new Response("boom", { status: 500 })) as typeof fetch;
  assertEquals(await consumeChatQuota("Bearer t", "https://x", "k", errored), { allowed: true, checkFailed: true });

  const malformed = (async () => new Response(JSON.stringify({ nope: 1 }), { status: 200 })) as typeof fetch;
  assertEquals(await consumeChatQuota("Bearer t", "https://x", "k", malformed), { allowed: true, checkFailed: true });

  const thrown = (async () => { throw new TypeError("network down"); }) as typeof fetch;
  assertEquals(await consumeChatQuota("Bearer t", "https://x", "k", thrown), { allowed: true, checkFailed: true });
});

Deno.test("limits leave headroom under Groq's free tier for a small household", () => {
  // ~1,000 requests/day per model x 3 models, <= 4 Groq calls per chat turn.
  assert(AI_CHAT_HOURLY_LIMIT > 0 && AI_CHAT_HOURLY_LIMIT <= AI_CHAT_DAILY_LIMIT, "hourly must be positive and <= daily");
  assert(AI_CHAT_DAILY_LIMIT * 4 <= 1000, "one user's daily cap must fit within a single model's daily request budget");
});

Deno.test("quotaExceededMessage rounds the wait up to friendly minutes/hours", () => {
  assert(quotaExceededMessage(30).includes("1 minute"), quotaExceededMessage(30));
  assert(quotaExceededMessage(1260).includes("21 minutes"), quotaExceededMessage(1260));
  assert(quotaExceededMessage(5 * 3600).includes("5 hours"), quotaExceededMessage(5 * 3600));
  assert(!/\\d+ seconds?/.test(quotaExceededMessage(1)), "never shows seconds");
});
