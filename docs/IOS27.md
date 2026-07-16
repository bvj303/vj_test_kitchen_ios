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

**Why Xcode 27 is now required to build this branch:** `AppleIntelligenceAIService`
references `PrivateCloudComputeLanguageModel`, which only exists in the iOS 27
SDK. It's runtime-gated with `#available(iOS 27, *)` so the app still *runs* on
iOS 26 (the deployment target stays **26.0** — the family's install is
unaffected), but it must *compile* against SDK 27. Foundation Models + the new
Vision OCR API otherwise shipped in the 26 SDK, so everything else is 26-native.

- The literal `deploymentTarget: 27.0` bump is **still not done and not needed** —
  keep the floor at 26.0 and gate 27-only APIs with `#available`.

## Done on this branch

- **Kitchen Concierge — on-device Apple Intelligence, escalating to Private
  Cloud Compute on iOS 27.** `AppleIntelligenceAIService` replaced the Gemini
  Edge Function. It grounds every reply in the user's real recipes (retrieval +
  structured-extraction, *not* model tool-calling — the small on-device model
  wasn't reliable at deciding to search, which read as "generic answers"). For
  the answer turn, `makeAnswerSession()` uses `PrivateCloudComputeLanguageModel`
  (a bigger, free/keyless/private Apple cloud model) when it reports available on
  iOS/macOS 27, and falls back to the on-device model on 26 / when PCC is
  unavailable. The cheap query-extraction stays on-device to conserve PCC quota.
  Verified: builds + 552 tests pass under Xcode 27 / iOS 27 SDK.
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

- [x] **`PrivateCloudComputeLanguageModel`** — **DONE** (see Done section). Apple's
      *larger* model on Private Cloud Compute, selectable via
      `LanguageModelSession(model: some LanguageModel, instructions:)`. Free (no
      cloud API cost under ~2M downloads), keyless, prompts not stored. Wired as
      the answer-turn model on iOS/macOS 27; on-device fallback on 26. Still
      available to layer on: the `reasoningLevel` context option and surfacing
      `quotaUsage` to the user.
- [x] **Unified `LanguageModel` protocol** — **DONE**: the escalation uses the
      generic `LanguageModelSession(model: some LanguageModel, …)` init, so
      swapping models is one line. (Third-party Anthropic/Google Swift packages
      also conform, if a non-Apple cloud is ever wanted.)
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
