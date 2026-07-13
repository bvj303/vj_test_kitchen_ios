# iOS 27 Release — Migration Checklist

This branch (`feature/ios27-apple-intelligence`) is the in-progress **iOS 27
version** of VJ Test Kitchen. It is intentionally kept separate from the
shipping iOS 26 line. This file tracks what's done, what's blocked on tooling,
and what's deferred.

## Toolchain requirement (blocker for the actual 27 build)

The dev machine currently has **Xcode 26.6 → iOS/macOS 26.5 SDK max**. You
**cannot** build against iOS 27, bump the deployment target to `27.0`, or use
any iOS-27-only API until **Xcode 27 is installed**. Everything below marked
"deferred (Xcode 27)" waits on that download — it's the one thing a background
job can't do for you.

The good news: Apple's `FoundationModels` and the new Swift `Vision` OCR API
both shipped in the **iOS/macOS 26** SDK. So the whole Apple-Intelligence
concierge + recipe-photo scanning already builds and is tested at deployment
target **26.0**, with no `@available` gating.

## Done on this branch (buildable + tested against the iOS 26 SDK)

- **Kitchen Concierge is now 100% on-device Apple Intelligence.**
  `AppleIntelligenceAIService` (`SystemLanguageModel.default` +
  `LanguageModelSession`) replaces the Gemini Edge Function entirely. Its one
  `searchRecipes` `Tool` runs in-process against the user's Supabase session, so
  recipe search is RLS-scoped with zero server-side auth plumbing.
- **Graceful degradation** on Apple-Intelligence-ineligible devices: the Planner
  shows an "unavailable" panel (`AIPlannerViewModel.unavailableReason`) and Siri
  surfaces the same copy, instead of a broken chat.
- **Recipe-photo scanning:** Vision `RecognizeTextRequest` OCRs a photo →
  `@Generable ScannedRecipe` structures it → prefills the recipe form
  (`RecipePhotoImportService`, `RecipeFormViewModel.apply(_:)`, the "Scan from
  Photo" `PhotosPicker` on the create form). Entirely on-device.
- **Siri** `PlanMealIntent` points at the on-device service.
- **Gemini removed:** `supabase/functions/ai-chat/` deleted from the repo.
- Tests: pure logic for prompt building, availability mapping, tool-result
  formatting, the recipe-reference sink, the ingredient-line parser, and the
  scan→form mapping. The **model/OCR calls themselves are not exercised** (the
  on-device model isn't available on the CI/build host) — a human needs to run
  the concierge + a photo scan once on a real Apple-Intelligence device.

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
      full-replace decision then if desired (DECISIONS.md, 2026-07-13).
- [ ] **Multimodal prompts** — pass the recipe *photo itself* to Foundation
      Models (instead of OCR-then-text), and use Vision tool-calling. Should
      improve extraction on messy layouts.
- [ ] **Next-gen Siri AI** — deeper App Intents surface for the concierge.
- [ ] **Evaluations framework** — quantify concierge answer quality as prompts
      change.

## Privacy / review notes

- No new "required reason" API was introduced. Vision OCR over local image bytes
  and FoundationModels need no new `PrivacyInfo.xcprivacy` entry; `PhotosPicker`
  is out-of-process (no `NSPhotoLibraryUsageDescription`). **Re-verify against
  the current App Review guidance before submission.**
- On-device generation means the concierge conversation and scanned recipe
  photos never leave the device — a privacy win worth noting in the listing.
