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
- [ ] **Free Private Cloud Compute** — enroll in the App Store Small Business
      Program (<2M downloads → free PCC). Lets the concierge escalate to a
      larger cloud model for hard asks at no API cost. iOS 27 only.
- [ ] **Unified any-model `LanguageModel` protocol** — iOS 27 lets Apple's model
      and cloud models sit behind one protocol, so a hybrid "on-device when
      eligible, PCC/cloud otherwise" becomes first-class. Revisit the
      full-replace decision then if desired (DECISIONS.md, 2026-07-13/15).
- [ ] **Multimodal prompts** — pass the recipe *photo/PDF page itself* to
      Foundation Models (instead of OCR-then-text). Should improve extraction on
      messy layouts.
- [ ] **Evaluations framework** — quantify concierge answer quality as prompts
      change.

## Privacy / review notes

- No new "required reason" API was introduced. Vision OCR over local image/PDF
  bytes and FoundationModels need no new `PrivacyInfo.xcprivacy` entry;
  `PhotosPicker` and `.fileImporter` are out-of-process (no
  `NSPhotoLibraryUsageDescription`). **Re-verify against the current App Review
  guidance before submission.**
- On-device generation means the concierge conversation, scanned recipe photos,
  and imported PDFs never leave the device — a privacy win worth noting in the
  listing.
