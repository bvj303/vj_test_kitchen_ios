// STREAMING SPIKE (not wired into production) — evaluates SSE token streaming
// for the Kitchen Concierge. See EVALUATION-streaming.md for the writeup.
//
// This module holds the load-bearing, zero-import logic that a streaming
// ai-chat would need on the SERVER side:
//   1. `SseDecoder` — turns Groq's `text/event-stream` bytes (which split
//      arbitrarily across TCP chunks) back into whole `data:` payload strings.
//   2. `groqDelta` — pulls the incremental token text out of one Groq payload.
//   3. `sseFrame` / SSE_DONE — frames OUR events to the client. We stream prose
//      tokens, then a single trailing `final` frame carrying the structured
//      recipes/actions (which can't ride the token stream), then `[DONE]`.
//
// The tricky part being proven here is (1): SSE parsing across chunk boundaries.
// The rest of a streaming ai-chat (run the tool loop non-streamed, then re-issue
// the FINAL completion with `stream: true` and pipe it through a ReadableStream
// Response) is sketched in EVALUATION-streaming.md — it needs a live Groq key,
// so it isn't unit-tested here.

// Self-contained on purpose (spike branch off main) — the real integration
// would import RecipeRef/ConciergeAction from search.ts instead of these.
type RecipeRefLike = { id: number; title: string };
type ConciergeActionLike = Record<string, unknown>;

// ── Frames WE send to the client (our own mini SSE protocol) ─────────────────

export interface TokenFrame {
  type: "token";
  text: string;
}

/// The final frame — sent after all prose tokens. Carries the structured payload
/// the token stream can't (recipes for cards, proposed write actions).
export interface FinalFrame {
  type: "final";
  recipes: RecipeRefLike[];
  actions: ConciergeActionLike[];
}

export type ConciergeStreamFrame = TokenFrame | FinalFrame;

export function sseFrame(frame: ConciergeStreamFrame): string {
  return `data: ${JSON.stringify(frame)}\n\n`;
}

export const SSE_DONE = "data: [DONE]\n\n";

// ── Decoding the UPSTREAM (Groq) SSE stream ──────────────────────────────────

/// Stateful decoder for an SSE byte stream. Feed it text chunks as they arrive
/// (which may split a line mid-way, or contain several lines) and it returns the
/// complete `data:` payload strings ready so far, buffering any partial trailing
/// line until the rest arrives. This is the piece that's easy to get wrong.
export class SseDecoder {
  private buffer = "";

  /// Push one chunk; get back zero or more complete `data:` payloads.
  push(chunk: string): string[] {
    this.buffer += chunk;
    const payloads: string[] = [];
    let newlineIndex: number;
    while ((newlineIndex = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, newlineIndex).replace(/\r$/, "");
      this.buffer = this.buffer.slice(newlineIndex + 1);
      if (line.startsWith("data:")) {
        payloads.push(line.slice("data:".length).trim());
      }
      // Non-data lines (event:, id:, comments, blank separators) are ignored —
      // Groq only uses `data:` lines.
    }
    return payloads;
  }
}

/// One Groq SSE `data:` payload → the incremental token (if any) and whether the
/// stream is done. Tolerant of malformed JSON (returns no content rather than
/// throwing), matching the resilience of the non-streaming parser.
export function groqDelta(payload: string): { content?: string; done: boolean } {
  if (payload === "[DONE]") return { done: true };
  try {
    const json = JSON.parse(payload);
    const delta = json?.choices?.[0]?.delta?.content;
    const finish = json?.choices?.[0]?.finish_reason;
    return {
      content: typeof delta === "string" ? delta : undefined,
      done: typeof finish === "string" && finish.length > 0,
    };
  } catch {
    return { done: false };
  }
}

/// Convenience: decode a whole sequence of Groq chunks into the assembled text.
/// Used by tests to prove decoder + delta compose correctly; the real streaming
/// path would instead forward each token to the client as it arrives.
export function assembleGroqStream(chunks: string[]): string {
  const decoder = new SseDecoder();
  let text = "";
  for (const chunk of chunks) {
    for (const payload of decoder.push(chunk)) {
      const { content } = groqDelta(payload);
      if (content) text += content;
    }
  }
  return text;
}
