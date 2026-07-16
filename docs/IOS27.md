# iOS 27 Release — Migration Checklist

The `ios27` branch is the in-progress **iOS 27 version** of VJ Test Kitchen,
kept separate from the shipping iOS 26 line so the app can adopt Apple
Intelligence and (later) iOS-27-only APIs without destabilizing `main`. This
file tracks what's done, what's blocked on tooling, and what's deferred.

## Toolchain reality (the one hard blocker for a literal "27" build)

As of 2026-07-15 the dev machine runs **macOS 27.0** but still has **Xcode 26.6
(iOS/macOS 26.5 SDK max)**. Installing **Xcode 27** is the one prerequisite a
background job can't do — it's a large download that needs the developer's Apple
ID. Until it's installed you **cannot**:

- bump the deployment target to `27.0`, or
- compile against any iOS-27-only API (Private Cloud Compute, the unified
  any-model `LanguageModel` protocol, Foundation Models multimodal image
  prompts).

**The good news is unchanged:** Apple's `FoundationModels` framework and the new
Swift `Vision` OCR API both shipped in the **iOS/macOS 26 SDK**. So every Apple
Intelligence feature below already builds and is tested at deployment target
**26.0**, with no `@available` gating — verified against the installed 26.5 SDK.

## Done on this branch (buildable + tested against the iOS 26 SDK)

- **Kitchen Concierge is now 100% on-device Apple Intelligence.**
  `AppleIntelligenceAIService` (`SystemLanguageModel.default` +
  `LanguageModelSession`) replaces the Gemini Edge Function entirely. Its
  `searchRecipes` `Tool` runs in-process against the user's Supabase session, so
  recipe search stays RLS-scoped with zero server-side auth plumbing.
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

- [ ] **`PrivateCloudComputeLanguageModel`** — Apple's *larger* model on Private
      Cloud Compute, selectable via `LanguageModelSession(model:)`. **No cloud
      API cost** to developers with <2M first-time downloads (this app easily
      qualifies), **no API key / auth**, prompts are **not stored** (stays in
      Apple's privacy envelope). 32K-token context, `reasoningLevel` context
      option. This is the clean answer to "use a bigger model" — strictly better
      than a third-party hybrid for this app's all-Apple/no-external-SDK ethos.
- [ ] **Unified `LanguageModel` protocol** — `SystemLanguageModel` (on-device)
      and `PrivateCloudComputeLanguageModel` both conform; swapping is one arg to
      `LanguageModelSession(model:)`, "everything downstream stays the same." So
      `AppleIntelligenceAIService` escalates to PCC on 27, on-device on 26, with
      no other changes. (Third-party Anthropic/Google Swift packages also
      conform, if a non-Apple cloud is ever wanted.)
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
