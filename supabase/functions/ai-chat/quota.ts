// Per-user rate limit for the Kitchen Concierge. Groq's free tier (~1,000
// requests/day per model) is shared by the whole household, and any
// authenticated user can call ai-chat — so one runaway client (a bug, a stuck
// retry loop, a curious teenager) must not burn everyone's quota. The count
// lives in Postgres behind a SECURITY DEFINER RPC keyed on auth.uid()
// (migration 20260927010000_ai_chat_rate_limit), called with the CALLER's
// token, so a user can only ever consume their own quota.
//
// Zero external imports, same constraint as index.ts / search.ts.

/// One user's cap. Each chat turn costs up to MAX_TOOL_ROUNDS (4) Groq calls, so
/// 150/day x 4 = 600 calls still fits inside one model's ~1,000/day budget.
export const AI_CHAT_HOURLY_LIMIT = 40;
export const AI_CHAT_DAILY_LIMIT = 150;

/// The quota check must never hang the chat.
const QUOTA_TIMEOUT_MS = 5_000;

export type QuotaResult =
  | { allowed: true }
  | { allowed: false; retryAfterSeconds: number }
  /// The check itself failed (DB/network). We fail OPEN — a quota outage must
  /// not take the concierge down — and the caller logs it.
  | { allowed: true; checkFailed: true };

export async function consumeChatQuota(
  authHeader: string,
  supabaseUrl: string,
  anonKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<QuotaResult> {
  try {
    const res = await fetchImpl(`${supabaseUrl}/rest/v1/rpc/consume_ai_chat_quota`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: authHeader, "Content-Type": "application/json" },
      body: JSON.stringify({ p_hourly_limit: AI_CHAT_HOURLY_LIMIT, p_daily_limit: AI_CHAT_DAILY_LIMIT }),
      signal: AbortSignal.timeout(QUOTA_TIMEOUT_MS),
    });
    if (!res.ok) {
      console.error("consume_ai_chat_quota failed:", res.status, await res.text());
      return { allowed: true, checkFailed: true };
    }
    const data = await res.json();
    if (typeof data?.allowed !== "boolean") return { allowed: true, checkFailed: true };
    if (data.allowed) return { allowed: true };
    const retry = Number(data.retry_after_seconds);
    return { allowed: false, retryAfterSeconds: Number.isFinite(retry) && retry > 0 ? Math.ceil(retry) : 60 };
  } catch (err) {
    console.error("consume_ai_chat_quota errored:", err);
    return { allowed: true, checkFailed: true };
  }
}

/// User-facing copy for a denied request (shown verbatim by the app).
export function quotaExceededMessage(retryAfterSeconds: number): string {
  const minutes = Math.max(1, Math.ceil(retryAfterSeconds / 60));
  const wait = minutes < 90
    ? `${minutes} minute${minutes === 1 ? "" : "s"}`
    : `${Math.ceil(minutes / 60)} hours`;
  return `You've reached the Kitchen Concierge's limit for now — please try again in about ${wait}.`;
}
