# iOS 27 Release — Migration Checklist

The `ios27` branch is the in-progress **iOS 27 version** of VJ Test Kitchen,
kept separate from the shipping iOS 26 line so the app can adopt Apple
Intelligence and (later) iOS-27-only APIs without destabilizing `main`. This
file tracks what's done, what's blocked on tooling, and what's deferred.

## Toolchain: this branch now builds with **Xcode 27**

As of 2026-07-15 **Xcode 27.0 is installed** at `/Applications/Xcode-beta.app`
(with the full `iPhoneOS27.0.sdk` / `iPhoneSimulator27.0.sdk`). Xcode 26.6 stays
the *selected* toolchain for the shipping app; build **this branch** with Xcode
27 via `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (no
`sudo`, no change to the global `xcode-select`). The deploy script honors
`DEVELOPER_DIR`, so `DEVELOPER_DIR=… scripts/deploy-testflight.sh --scheme
VJTestKitchenAIBeta` ships the beta.

**The branch currently builds on either Xcode 26.6 or 27** — the one iOS-27-only
symbol (`PrivateCloudComputeLanguageModel`) was reverted after it crashed (see
the PCC bullet below), so there's no hard SDK-27 dependency right now. Xcode 27
is only *needed* again when PCC (or another 27-only API) is re-introduced; build
that with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

- The literal `deploymentTarget: 27.0` bump is **still not done and not needed** —
  keep the floor at 26.0 and gate 27-only APIs with `#available`.

## Done on this branch

- **Kitchen Concierge — now Groq cloud (free), was on-device.** As of 2026-07-16
  the shipping chatbot is the **Groq free tier** (`llama-3.3-70b-versatile`) via
  the restored `ai-chat` Edge Function (cloud-only) — a big quality jump over the
  ~3B on-device model, still $0 (1,000 req/day), key server-side, RLS-scoped
  search, and Groq doesn't train on your data. See DECISIONS.md (2026-07-16).
  The on-device `AppleIntelligenceAIService` (grounded retrieval) is retained for
  its availability helper (used by the scan/smarts below) but no longer wired as
  the concierge. *This supersedes the earlier on-device/PCC concierge direction
  for the chatbot specifically* — PCC stays a future option if its entitlement is
  ever granted. Requires `GROQ_API_KEY` as a prod Edge Function secret.
- **Private Cloud Compute escalation — implemented then REVERTED (build 8 crashed).**
  `makeAnswerSession()` briefly used `PrivateCloudComputeLanguageModel` on iOS 27.
  It shipped as beta build 8 and **hard-crashed** on the device: PCC is
  **entitlement-gated** (`com.apple.developer.private-cloud-compute` + App Store
  Small Business Program enrollment, <2M downloads), and *touching* the PCC type
  without the entitlement **traps** — not a catchable error. Reverted to
  on-device in build 9. The escalation code is one `git revert` away in history;
  re-enable only after: (1) enroll in the Small Business Program, (2) request/get
  the PCC entitlement on the App ID, (3) confirm the signed build carries it.
  Until then the branch builds on **either** Xcode 26.6 or 27 (no PCC symbol).
- **Graceful degradation** on Apple-Intelligence-ineligible devices (and the
  Simulator, which has no model): the Planner shows an "unavailable" panel
  (`AIPlannerViewModel.unavailableReason`), the scanner/writing-tools buttons
  hide, and Siri surfaces the same copy — no broken UI.
- **Recipe scanning — photo *and* PDF.** `RecipePhotoImportService`:
  - *Photo:* Vision `RecognizeTextRequest` OCRs the image.
  - *PDF/document:* PDFKit reads the embedded text layer; for scanned/image-only
    PDFs it falls back to rasterizing each page with **Core Graphics** (no
    UIKit/AppKit — same ethos as `AvatarImageProcessor`) and OCRing it.
  - Either way, a `@Generable ScannedRecipe` structures the text and prefills the
    Add-Recipe form. Entirely on-device. The Mac target got the
    `files.user-selected.read-only` sandbox entitlement for the PDF importer.
- **On-device recipe smarts** (`RecipeWritingService`): "Generate Description"
  and "Suggest Tags" buttons on the recipe form, both Foundation-Models-backed
  and availability-gated. Tag suggestions prefer the catalog's existing tag
  vocabulary so tags don't fragment.
- **Deeper Siri / App Intents:** two new intents that work on **every** device
  (no Apple Intelligence needed) — `FindRecipeIntent` (search your collection)
  and `AddGroceryItemIntent` (add to the grocery list, aisle-categorized via the
  existing `GroceryCategorizer`), both registered in `VJTestKitchenShortcuts`.
- **System Writing Tools:** `.writingToolsBehavior(.complete)` on the recipe
  Description + Instructions fields.
- **Gemini removed:** `supabase/functions/ai-chat/` deleted from the repo; the
  client no longer references it.
- Tests: pure logic for prompt building, availability mapping, tool-result
  formatting, the recipe-reference sink, the ingredient-line parser, the
  scan→form mapping, description/tag prompt building + cleaning, tag merging,
  and the Siri find-recipe dialog. The **model/OCR calls themselves are not
  exercised** (the on-device model isn't available on the CI/build host) — a
  human needs to run the concierge, a photo scan, a PDF import, and the
  generate/suggest buttons once on a real Apple-Intelligence device.

## Pending remote actions (user must run — bg jobs can't hit remote Supabase)

- [ ] `supabase functions delete ai-chat` — remove the now-orphaned deployed
      function. Nothing in the client calls it, so this is cleanup, not a
      blocker.
- [ ] `supabase secrets unset GEMINI_API_KEY` — the key is unused now.

## Deferred until Xcode 27 is installed

- [ ] **Bump deployment targets to `27.0`** in `project.yml` (all six targets)
      and re-run `xcodegen generate`. One-line-per-target change; the drift
      guards handle the rest.
These are **confirmed** in the iOS 27 SDK (Apple WWDC26 session 241, "What's new
in the Foundation Models framework") — they need the **full** iOS 27 SDK to
compile (the slim Xcode 27 install has no platform SDKs) and `#available(iOS 27,
*)` gating so iOS-26 devices (the family) fall back to the on-device model.

- [ ] **`PrivateCloudComputeLanguageModel`** — API usage was correct (matches
      Apple's sample; built + tested under Xcode 27), but **blocked on a managed
      entitlement**. Per Apple's doc ("Adding server-side intelligence with
      Private Cloud Compute"): the key is `com.apple.developer.private-cloud-compute`,
      and it's a **managed entitlement you must REQUEST ACCESS to at
      https://developer.apple.com/private-cloud-compute/** — Apple approves it; it
      is **NOT** auto-granted by App Store Small Business Program enrollment (the
      <2M-downloads/Small-Business bit is only the free *cost* tier). Touching the
      type without the entitlement kills the app (crashed beta build 8).
      **When re-landing, also add what our first cut missed** (both in Apple's
      doc): (a) network-failure fallback — wrap `respond` in try/catch and retry
      on `SystemLanguageModel()` if PCC fails (PCC needs network); (b) quota
      awareness via `model.quotaUsage` (`.isLimitReached`, `resetDate`,
      `limitIncreaseSuggestion.show()`); optional `ContextOptions(reasoningLevel:)`.
      Selectable via `LanguageModelSession(model: some LanguageModel, instructions:)`;
      free (<2M downloads), keyless, prompts not stored.
- [~] **Unified `LanguageModel` protocol** — the generic
      `LanguageModelSession(model: some LanguageModel, …)` init is confirmed and
      was used for the (reverted) PCC path; re-lands with PCC.
- [ ] **Multimodal prompts** — attach the recipe *photo/PDF page itself*
      (`Attachment(UIImage/CGImage/…)`) instead of OCR-then-text. Should improve
      extraction on messy layouts.
- [ ] **Bump deployment target to 27.0** is NOT required for the above — keep the
      floor at 26.0 (family) and gate the 27 APIs with `#available`.
- [ ] **Evaluations framework** — quantify concierge answer quality as prompts
      change.

**Correction (2026-07-15):** an earlier verbal claim in this session that Apple's
cloud models aren't available to third-party apps was true for iOS **26** only —
iOS **27** opens PCC to developers as above. The "free PCC under ~2M downloads"
note was correct.

## Privacy / review notes

- No new "required reason" API was introduced. Vision OCR over local image/PDF
  bytes and FoundationModels need no new `PrivacyInfo.xcprivacy` entry;
  `PhotosPicker` and `.fileImporter` are out-of-process (no
  `NSPhotoLibraryUsageDescription`). **Re-verify against the current App Review
  guidance before submission.**
- On-device generation means the concierge conversation, scanned recipe photos,
  and imported PDFs never leave the device — a privacy win worth noting in the
  listing.
