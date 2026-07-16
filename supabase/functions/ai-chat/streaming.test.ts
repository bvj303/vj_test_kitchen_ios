// Tests for the streaming spike's load-bearing SSE logic. Zero imports, same as
// the rest of ai-chat. Run: deno test supabase/functions/ai-chat/streaming.test.ts
import { assembleGroqStream, groqDelta, SseDecoder, sseFrame, SSE_DONE } from "./streaming.ts";

function assertEquals(actual: unknown, expected: unknown, msg?: string) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(msg ?? `expected ${e}, got ${a}`);
}
function assert(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

Deno.test("SseDecoder yields complete data payloads and buffers a partial trailing line", () => {
  const d = new SseDecoder();
  // A chunk that ends mid-line — the partial `data: {"choices"...` must be held.
  const first = d.push('data: {"a":1}\ndata: {"b":2}\ndata: {"c"');
  assertEquals(first, ['{"a":1}', '{"b":2}']);
  // The rest of the split line arrives in the next chunk.
  const second = d.push(':3}\n');
  assertEquals(second, ['{"c":3}']);
});

Deno.test("SseDecoder handles CRLF line endings and ignores non-data lines", () => {
  const d = new SseDecoder();
  const out = d.push("event: message\r\ndata: {\"x\":1}\r\n\r\n: a comment\r\n");
  assertEquals(out, ['{"x":1}']);
});

Deno.test("groqDelta extracts the incremental token, detects done, and tolerates junk", () => {
  assertEquals(groqDelta('{"choices":[{"delta":{"content":"Hel"}}]}'), { content: "Hel", done: false });
  assertEquals(groqDelta('{"choices":[{"delta":{},"finish_reason":"stop"}]}'), { content: undefined, done: true });
  assertEquals(groqDelta("[DONE]"), { done: true });
  assertEquals(groqDelta("not json"), { done: false });
});

Deno.test("decoder + delta compose to reassemble the full streamed answer across arbitrary chunk splits", () => {
  // The same answer, delivered in awkward chunk boundaries (mid-token, mid-line).
  const chunks = [
    'data: {"choices":[{"delta":{"content":"Try "}}]}\n',
    'data: {"choices":[{"delta":{"content":"the Coq"}}]}\ndata: {"choices":[{"delta":{"content":" au ',
    'Vin."}}]}\n',
    'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n',
    "data: [DONE]\n",
  ];
  assertEquals(assembleGroqStream(chunks), "Try the Coq au Vin.");
});

Deno.test("sseFrame + SSE_DONE emit well-formed downstream SSE frames", () => {
  assertEquals(sseFrame({ type: "token", text: "hi" }), 'data: {"type":"token","text":"hi"}\n\n');
  const final = sseFrame({ type: "final", recipes: [{ id: 2, title: "Beef Tacos" }], actions: [] });
  assert(final.startsWith("data: ") && final.endsWith("\n\n"), "final frame must be an SSE data event");
  assert(JSON.parse(final.slice(6)).type === "final", "final frame decodes to a final event");
  assertEquals(SSE_DONE, "data: [DONE]\n\n");
});
