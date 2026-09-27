# iOS 27 — one app, consolidated

As of 2026-09-27 there is **one app** (`VJTestKitchen`, bundle
`com.bvj303.vjtestkitchen`, plus its native macOS sibling `VJTestKitchenMac`).
The separate `ios27` branch and its **"VJTK AI"** TestFlight POC target
(`VJTestKitchenAIBeta`, bundle `com.bvj303.vjtestkitchen.aibeta`) are retired:
everything worth keeping from them now lives on `main`. See DECISIONS.md
(2026-09-27).

## Toolchain

- Builds and tests on **Xcode 26.x and Xcode 27** (Xcode 27 lives at
  `/Applications/Xcode-beta.app`; use
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` — no `sudo`,
  no change to the global `xcode-select`). Verified: the full unit suite passes
  on an **iOS 27.0 simulator** built with the iOS 27 SDK, and on iOS 26.
- **Deployment target stays 26.0** (iOS/iPadOS/macOS). Everything below ships in
  the 26 SDK, so iOS 27 users get all of it while family devices still on 26
  keep getting updates. Gate any future 27-only API with `#available(iOS 27, *)`.
  Bumping the floor to 27.0 is a one-line-per-target `project.yml` change if we
  ever want to drop 26.
- `scripts/deploy-testflight.sh` honors `DEVELOPER_DIR`, so an Xcode-27-built
  archive of the one app is `DEVELOPER_DIR=… scripts/deploy-testflight.sh`.

## What's in the app (from the former `ios27` branch)

- **Recipe scanning — photo and PDF** (`RecipePhotoImportService`): Vision
  `RecognizeTextRequest` OCRs a photo; for a PDF, PDFKit reads the text layer
  and falls back to Core-Graphics rasterization + OCR for scanned pages. A
  `@Generable ScannedRecipe` structures the text on-device and prefills the Add
  Recipe form (`RecipeIngredientLineParser` splits "2 cups flour" into rows). The
  Mac target has the `files.user-selected.read-only` sandbox entitlement for the
  PDF importer.
- **Recipe smarts** (`RecipeWritingService`): "Generate Description" and
  "Suggest Tags" on the recipe form (tags prefer the catalog's existing
  vocabulary), plus system Writing Tools on Description/Instructions.
- **Siri / Shortcuts**: `FindRecipeIntent` and `AddGroceryItemIntent` (work on
  every device — no Apple Intelligence needed), alongside `PlanMealIntent`.
- All on-device features gate on `AppleIntelligenceAvailability` — their buttons
  hide on ineligible devices and the Simulator rather than leading to a dead end.

## The Kitchen Concierge (AI Planner) is cloud, not on-device

The concierge runs on **Groq's free tier** through the `ai-chat` Edge Function
(model chain `openai/gpt-oss-120b` → `qwen/qwen3.8-27b` → `openai/gpt-oss-20b`,
key server-side, RLS-scoped pgvector search). Why not Apple Intelligence:

- The ~3B **on-device** model didn't reliably tool-call (answers went generic;
  grounding-in-prompt helped but it's still a small model), and it's absent on
  ineligible devices, the Simulator, and Macs without Apple Intelligence — the
  cloud concierge works everywhere.
- **Private Cloud Compute** (`PrivateCloudComputeLanguageModel`, iOS 27) is the
  interesting option — larger, free under ~2M downloads, keyless, private — but
  it needs the **managed entitlement** `com.apple.developer.private-cloud-compute`,
  requested at https://developer.apple.com/private-cloud-compute/ (Apple
  approves; not automatic). *Touching the type without the entitlement traps* —
  that crashed beta build 8. When/if it's granted: re-land from commit `1ca407e`
  (on the archived `ios27` branch) as a **fallback** tier behind the cloud chain,
  with Apple's recommended network-failure retry on the on-device model and
  `quotaUsage` handling. The grounded on-device concierge
  (`AppleIntelligenceAIService`) is also preserved on that branch.

## Still to verify by hand (needs a real Apple-Intelligence device)

The model/OCR round-trips can't run on the Simulator or CI. Once on a real
device: scan a recipe photo, import a PDF, tap Generate Description and Suggest
Tags, and try "Find a recipe in VJ Test Kitchen" / "Add to my VJ Test Kitchen
grocery list" via Siri.

## Future iOS 27 options

- [ ] PCC concierge fallback (blocked on the entitlement — see above).
- [ ] Multimodal prompts — attach the recipe photo/PDF page itself
      (`Attachment(…)`) instead of OCR-then-text, for messy layouts.
- [ ] Replace the deprecated `CLGeocoder` calls in `GeocodingProviding` with
      `MKGeocodingRequest` / `MKReverseGeocodingRequest`.

## Privacy / review notes

- No new "required reason" API. Vision OCR and FoundationModels need no new
  `PrivacyInfo.xcprivacy` entry; `PhotosPicker` and `.fileImporter` are
  out-of-process (no `NSPhotoLibraryUsageDescription`).
- Scanned photos/PDFs and generated descriptions/tags never leave the device.
  Concierge chats go to Groq (which doesn't train on API data) — re-verify the
  App Privacy answers before submission.
