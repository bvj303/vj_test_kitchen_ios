# Streaming spike — evaluation

**Question:** should the Kitchen Concierge stream its answer (SSE token-by-token)
instead of returning it all at once? Requested as "prototype it anyway, evaluate
feel/complexity before deciding."

**Verdict: feasible and cheaper than the original plan assumed, but the ROI is
modest. Recommend measuring real latency first; ship later behind a flag if the
*final-answer* wait is actually felt — reusing the tested parsers in this spike.
Do NOT block Slices 1–3 on it.**

This branch (`spike/concierge-streaming`) is a spike: the load-bearing logic is
built and unit-tested; it is **not** wired into the production flow.

## What changed vs. the plan's assumption

The plan flagged the client as the blocker: *"supabase-swift's `functions.invoke`
doesn't stream; you'd hand-roll a URLSession SSE path."* That's **wrong** — the
SDK already ships `FunctionsClient._invokeWithStreamedResponse(_:options:) ->
AsyncThrowingStream<Data, Error>` (read it in
`SourcePackages/checkouts/supabase-swift/Sources/Functions/FunctionsClient.swift:269`).
It forwards our headers/body via the same `buildRequest`, uses a private
`URLSession` + delegate, and yields raw `Data` chunks. So the client does **not**
need a bespoke networking stack — just SSE parsing on the yielded chunks.

Caveat: it's **underscore-prefixed and documented "Experimental — the API may
change without a major version bump."** Depending on it is a real (if small)
maintenance risk.

## Both constraints hold

- **Zero external imports:** streaming is a plain `Response` with a
  `ReadableStream` body + `Content-Type: text/event-stream`. `Deno.serve`
  supports it with built-ins only. Groq streams via `stream: true` on the same
  `chat/completions` endpoint we already `fetch`. No npm/jsr. ✅
- **RLS / auth:** unchanged — same forwarded token, same tool loop, same
  `match_recipes`/PostgREST reads. Streaming only changes how the *final text* is
  delivered. ✅

## The design (sketch)

The tool loop can't stream: you don't know the answer until the tools resolve. So
streaming covers only the **final** completion:

1. Run `runGroqWithTools` exactly as today **until the model stops calling tools**
   (all tool rounds non-streamed — the user sees "Thinking…").
2. Re-issue that final completion with `stream: true`. Pipe it through a
   `ReadableStream`:
   - decode Groq's SSE with `SseDecoder` + `groqDelta` (this spike, tested),
   - for each token, enqueue `sseFrame({ type: "token", text })`,
   - after `[DONE]`, enqueue **one** `sseFrame({ type: "final", recipes, actions })`
     — the structured payload can't ride the token stream — then `SSE_DONE`.
3. Client consumes via `_invokeWithStreamedResponse`, runs the **same** SSE
   decode (a Swift port of `SseDecoder`), appends `token` frames to the streaming
   bubble live, and applies the `final` frame's recipes/actions at the end.

Non-streaming `ai-chat` stays as the default and the fallback (Siri has no UI to
stream into; a decode error falls back cleanly).

### Client wiring (sketch, not built)
```swift
func sendMessageStreaming(_ history: [AIChatTurn]) -> AsyncThrowingStream<AIStreamEvent, Error> {
    // token = try await client.auth.session.accessToken  (as today)
    let dataStream = client.functions._invokeWithStreamedResponse(
        "ai-chat",
        options: FunctionInvokeOptions(headers: ["Authorization": "Bearer \(token)"],
                                       body: RequestBody(messages: history, stream: true))
    )
    // AsyncThrowingStream that pipes dataStream through a Swift SseDecoder,
    // JSON-decodes each `data:` payload into .token(String) / .final(recipes,actions).
}
```
`AIPlannerViewModel.send()` would append an empty assistant bubble and mutate its
`content` per `.token`, then set `recipes`/`actions` on `.final`.

## Why the ROI is modest (the honest part)

- **Tool rounds don't stream.** The concierge's *slow* case is a multi-search
  menu (several Groq round-trips + embeds + RPCs). All of that still shows a
  plain spinner; only the closing prose streams. Streaming helps the simple
  single-answer case most — which is already the *fast* case on Groq.
- **Groq is genuinely fast.** The felt latency today is dominated by tool rounds,
  not final-token generation.
- **Real added surface:** a second server path (streamed vs. buffered), a custom
  two-part framing (tokens + trailing structured frame) kept in sync with the
  JSON response, a Swift SSE decoder, streamed error handling, and a dependency
  on an `_experimental` SDK method.

## Recommendation

1. **Now:** don't ship. Keep the "Thinking…" indicator.
2. **Measure:** add the `groq_round` latency logging from Slice 1 (already done)
   to capture real p50/p95 of (a) total turn and (b) final-round only in the
   running app.
3. **If the final-round wait is actually felt:** ship streaming behind a settings/
   remote flag, reusing `SseDecoder`/`groqDelta`/`sseFrame` (tested here) + the
   `_invokeWithStreamedResponse` path above. Keep non-streaming as the fallback.

## What was verified here

- `deno check` clean; `deno test streaming.test.ts` → 5 passing, covering the
  genuinely tricky bit: SSE reassembly across arbitrary chunk boundaries (partial
  trailing lines, CRLF, non-data lines), token extraction, done detection, and
  downstream frame formatting.
- **Not verified:** live end-to-end streaming (needs the real `GROQ_API_KEY` and a
  device/simulator) — same caveat pattern as the rest of the concierge work.
