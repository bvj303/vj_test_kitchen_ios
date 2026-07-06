# Decisions Log

Running log of architectural/product decisions for the VJ Test Kitchen iOS rebuild. Each entry: date, decision, what was considered, why we chose what we chose.

## 2026-07-05 — Retire the old stack entirely, rebuild native
**Decision**: Fully retire the React frontend, Express backend, and Railway hosting. No website will exist going forward — the SwiftUI app is the only client.
**Considered**: Keeping the web app running alongside a new iOS app (rejected — user is the only user right now, so there's no audience to serve on web, and running two stacks would double maintenance for no benefit). Porting the React app to a PWA/wrapped app instead of native (rejected — user explicitly wants a first-class native iPhone/iPad experience with platform APIs like PhotosPicker/camera capture and iPad-specific layouts).

## 2026-07-05 — Supabase over continuing custom Express/Postgres/Railway backend
**Decision**: Backend moves to Supabase (Postgres + Auth + Storage + Edge Functions).
**Considered**: Keeping the existing Express API and just pointing a new SwiftUI client at it (rejected — would still require maintaining Railway hosting, hand-rolled JWT/bcrypt auth, and multer/R2 upload plumbing for a single-user app; Supabase gives auth, storage, and RLS out of the box). Firebase (rejected — Firestore's NoSQL document model would require redesigning the existing relational schema — recipes/ingredients/tags/recipe_tags/meal_plans — that already maps cleanly onto Postgres tables). Self-hosting Supabase vs. hosted (deferred — using hosted Supabase for now since there's no migration pressure or scale concern yet).

## 2026-07-05 — Native SwiftUI, iOS/iPadOS 18+ only
**Decision**: Universal SwiftUI app (iPhone + iPad), minimum deployment target iOS 18 / iPadOS 18.
**Considered**: Supporting iOS 17+ for broader compatibility (rejected — user is the only user and controls their own devices, so there's no back-compat burden; targeting only the latest major version keeps access to the newest SwiftUI/Swift 6 APIs without availability checks).
**Superseded 2026-07-06** — see below: bumped to iOS 26+ once Liquid Glass entered scope.

## 2026-07-06 — Bumped minimum deployment target to iOS/iPadOS 26+ for Liquid Glass
**Decision**: Raised the minimum deployment target from iOS 18 to iOS 26, so the app can use Apple's Liquid Glass design language (`.glassEffect()`, the new tab bar/sidebar/toolbar materials, `.glassProminent` button style, etc.) natively everywhere, with no availability fallback branches.
**Considered**: Keeping iOS 18+ and gating Liquid Glass behind `if #available(iOS 26, *)` with a plainer fallback appearance on 18-25 (rejected — user explicitly wants Liquid Glass as a core part of the visual identity, not a nice-to-have; maintaining two visual codepaths for a compatibility range the sole user doesn't need would be pure overhead. Their own dev tooling is already iOS 26.5 SDK / Xcode 26.6, reinforcing there's no real device-compatibility need being served by staying on 18).
**Why this is safe to revisit again later**: still just the sole-user, no-migration-pressure phase — if the app is ever shared beyond one person on older devices, this is the number to reconsider, same as the `mailer_autoconfirm` auth setting.

## 2026-07-05 — Swift Testing over XCTest
**Decision**: Use Swift Testing (`@Test`, `#expect`) for the app's test suite.
**Considered**: XCTest (rejected — more mature and has more tutorial coverage, but this is a greenfield project with no legacy test suite to stay compatible with; Swift Testing's macro-based syntax is a better fit for the mandatory TDD workflow going forward).

## 2026-07-05 — Bundle identifier: com.bvj303.vjtestkitchen
**Decision**: Use `com.bvj303.vjtestkitchen` as the app's bundle ID prefix.
**Considered**: A custom domain-based identifier (not available — user doesn't currently own a domain to reverse for this); GitHub-username-based reverse-DNS was chosen as a stable, unlikely-to-collide identifier.

## 2026-07-05 — Gemini model and key handling
**Decision**: Keep `gemini-3.1-flash-lite` (same model the old Express backend used in `backend/ai.js`) for AI menu planning, called from a Supabase Edge Function with the API key stored as a Supabase secret.
**Considered**: Switching to `gemini-3.5-flash` (rejected — the old app specifically chose `-3.1-flash-lite` for its higher free-tier daily quota; no new reason to change that has come up). Calling Gemini directly from the client (rejected — would expose the API key; explicit requirement from the user that the key never lives in the client).

## 2026-07-05 — Export-to-Reminders via native EventKit, not a server call
**Decision**: Preserve the "export grocery list to Apple Reminders" feature, reimplemented natively using EventKit (`EKEventStore`, reminders access) directly on-device.
**Considered**: Porting the old mechanism as-is — an Express route on the Railway host shelling out to AppleScript via `osascript` (rejected — there's no macOS server to shell out from anymore, and it required backend to double as a controller of the user's own Mac; on-device EventKit is strictly simpler, needs no network round-trip, and is the standard iOS-native way to write to Reminders).

## 2026-07-05 — Recipes stay a shared household recipe box; meal plans stay private
**Decision**: Carry over the old app's model exactly — every authenticated user can read every recipe and update `rating`/`notes` on any recipe; only the creator can edit/delete a recipe's core fields (title, instructions, ingredients, etc). Meal plans remain strictly `user_id`-scoped (private per-user calendars).
**Considered**: Switching to fully private per-user recipes (rejected — would change real product behavior from the old app, and the user confirmed the shared model is intentional, not an oversight). This shapes RLS: recipes need row-level SELECT open to all authenticated users but owner-gated UPDATE/DELETE, plus a separate mechanism for the anyone-can-rate exception (see schema proposal) since plain RLS policies can't split permissions by column.

## 2026-07-05 — Supabase project created; service_role key exposure noted, not rotated
**Decision/note**: Project `aviyhrmjsqygoyzjprii` (us-east-2, Postgres 17) created and linked via CLI. While fetching the anon key for client config, a CLI command (`supabase projects api-keys`) also printed the full `service_role` key (and legacy anon JWT) into the chat transcript. User was informed this key bypasses RLS entirely and offered the choice to rotate it immediately; **user chose not to rotate it** and to continue as-is, since this is a personal test project with no sensitive data yet.
**Why this matters going forward**: if this project ever holds real/sensitive data, or before any wider sharing of this repo/transcript, the `service_role` key should be rotated in Settings → API. Future sessions should avoid running commands that dump all API keys at once — fetch only the specific key needed (e.g. filter for `"publishable"`/`"anon"`) or have the user copy it from the dashboard directly.

## 2026-07-05 — Drop AI recipe import from URL/PDF
**Decision**: Do not carry over `/api/ai/import-url` / `/api/ai/import-pdf` (Gemini-powered recipe extraction from a pasted URL or uploaded PDF). Only the menu-planning AI feature moves forward into the new app.
**Considered**: Preserving it as a second Edge Function (rejected for now — user chose to drop it; not on the original preserve list, and recipes can still be entered manually or via the existing Python ATK scraper for Stage 8's content load). Can be revisited later as a Stage 9+ addition if wanted.

## 2026-07-06 — recipes.user_id survives creator deletion (ON DELETE SET NULL)
**Decision**: Changed from the old app's `ON DELETE CASCADE` (deleting a user deleted all their recipes) to `ON DELETE SET NULL` — a recipe stays in the shared household box even if its creator's account is later deleted.
**Considered**: Matching the old CASCADE behavior exactly (rejected — user confirmed the SET NULL behavior is preferred, since it fits a shared multi-person household box better than treating recipes as owned-and-disposable by a single account).

## 2026-07-06 — Ratings/notes become personal per-user, not a shared recipe field
**Decision**: Dropped `recipes.rating`/`recipes.notes` entirely. Added a new `recipe_ratings` table (`recipe_id, user_id, rating, notes`, one row per user per recipe), strictly private via RLS (`auth.uid() = user_id`) — no aggregate/average rating is computed or shown anywhere.
**Considered**: Keeping the old app's single shared `rating`/`notes` per recipe, editable by anyone (rejected — user explicitly wants independent personal ratings once there's more than one household member). A `SECURITY DEFINER` RPC function to let any user write a shared rating/notes field while still restricting other columns (considered and prototyped, then discarded once ratings became per-user — a private per-user table with plain RLS is simpler and needed no special-cased function). Showing an average rating alongside "my rating" (rejected for now — user wants just their own rating, no aggregate; can add a view later without a schema change since it wouldn't need a stored column).

## 2026-07-06 — Schema validated locally before touching the remote project
**Decision**: Applied the initial migration to the local Supabase stack (`supabase start` + migration auto-apply) and hand-verified RLS with two seeded `auth.users` rows (simulating `auth.uid()` via `request.jwt.claims`) before running `supabase db push` against the real hosted project.
**Why**: schema/RLS mistakes are easy to make and annoying to unwind on a live project; local verification is fast and free. Confirmed: shared recipe read/owner-only write, private per-user ratings (including that another user's rating stays invisible even on a recipe you created), and private meal plans (including that they stay invisible to other users even when referencing a shared recipe).

## 2026-07-06 — Found and fixed: hosted project auto-granted `anon` role access
**Decision/finding**: An unauthenticated `curl` against the remote project's `/rest/v1/recipes` returned `200 []` (not a permission error), while the identical test against the local stack correctly returned `401`. Root cause: the hosted Supabase project appears to auto-grant some default privileges to `anon` at project-creation time, independent of `supabase/config.toml`'s `auto_expose_new_tables` setting (which only governs the local CLI stack). Fixed with an explicit migration (`20260706020000_revoke_anon_access.sql`) that revokes all schema/table/sequence/function privileges from `anon` and sets default privileges so future tables don't inherit access either. Re-verified remote now returns `401` like local.
**Why this matters going forward**: don't assume RLS policies alone are sufficient on a hosted project — table-level grants can differ between local and remote even with identical migrations applied. Always verify unauthenticated access is actually blocked against the real remote project, not just locally.

## 2026-07-06 — xcodegen instead of a hand-authored/GUI-created .xcodeproj
**Decision**: Generate `VJTestKitchen.xcodeproj` from a tracked `project.yml` via `xcodegen generate`; the `.xcodeproj` itself is gitignored and regenerated on demand.
**Considered**: Driving Xcode's GUI "New Project" wizard (not possible — no way to script/automate Xcode's project-creation UI from this session). Hand-authoring the `.pbxproj` XML directly (rejected — extremely easy to corrupt, no schema validation, painful to review in diffs). `xcodegen`'s YAML spec is declarative, diffable, and regenerates deterministically.

## 2026-07-06 — Custom Info.plist instead of GENERATE_INFOPLIST_FILE
**Decision**: The app target uses a real, hand-written `VJTestKitchen/Resources/Info.plist` (via `INFOPLIST_FILE`) instead of Xcode's `GENERATE_INFOPLIST_FILE` + `INFOPLIST_KEY_*` auto-synthesis.
**Why**: Discovered empirically — `INFOPLIST_KEY_SUPABASE_URL`/`INFOPLIST_KEY_SUPABASE_ANON_KEY` resolved correctly as *build settings* (confirmed via `xcodebuild -showBuildSettings`) but never actually appeared in the generated `Info.plist`. Xcode's auto-generation only synthesizes a fixed list of Apple-known keys (launch screen, supported orientations, etc.); arbitrary custom keys are silently dropped. Caught this before it could crash the app at Stage 4 (auth) — the build and initial UI screenshot looked fine because nothing yet touched `SupabaseManager.client`, which would have been the first thing to hit the missing config and crash via `fatalError`. Verified the fix by temporarily forcing `SupabaseManager.client` access in `ContentView` and confirming it printed the correct Supabase host with no crash, before reverting that temporary code.
**Considered**: Continuing to try to coerce `INFOPLIST_KEY_*` into working (rejected — it's a fixed Apple-defined key list, not a generic mechanism, per Xcode's actual behavior observed). Hardcoding the URL/key as Swift string literals (rejected — defeats the whole point of keeping config out of source and environment-flexible).

## 2026-07-06 — AppConfig takes an injectable Bundle instead of hardcoding Bundle.main
**Decision**: `AppConfig.supabaseURL(bundle:)`/`supabaseAnonKey(bundle:)` default to `Bundle.main` but accept an override; tests build a real temp-directory-backed `Bundle` with their own `Info.plist` rather than relying on `Bundle.main`.
**Why**: Swift Testing unit tests (unhosted, no `TEST_HOST`) don't run inside the app process — `Bundle.main` in that context resolves to the test runner, not the app, so it can never see the real Info.plist. An earlier attempt to fix this by manually wiring `TEST_HOST`/`BUNDLE_LOADER` build settings broke simulator launch entirely ("Application failed preflight checks") and was reverted. Bundle injection sidesteps the whole hosted-vs-unhosted test question and tests `AppConfig`'s own parsing/validation logic directly.
**Considered**: `Bundle(for:)` on a marker class compiled into the app module (tried — did not resolve to the app bundle from an unhosted test process either, since the module's code loads into the test bundle's own binary in that configuration). Proper hosted-test wiring via `TEST_HOST` (rejected — broke the simulator launch; not worth the fragility for what bundle injection solves more simply).

## 2026-07-06 — Auth: AuthServicing protocol decoupled from supabase-swift's Session type
**Decision**: `AuthViewModel` depends on an `AuthServicing` protocol (`signUp`/`signIn`/`signOut` + `userIdChanges: AsyncStream<UUID?>`), not directly on `SupabaseClient.auth` or its `Session`/`User` types. Tests use a `FakeAuthService` that never constructs a real `Session`.
**Considered**: Testing against real `Session`/`User` values, e.g. by decoding sample JSON the way `RecipeModelTests` does for Postgrest models (rejected — supabase-swift's Auth types aren't part of this app's own schema/contract the way Postgrest rows are; pinning tests to their exact Codable shape would make tests fragile to SDK internals we don't control, for no real benefit since the view model only ever needs a user id). This also kept `AuthViewModel` itself SDK-agnostic, matching the Service-layer pattern established in Stage 3.

## 2026-07-06 — Auto-confirm signups during solo testing (mailer_autoconfirm = true)
**Decision**: Set the hosted project's `mailer_autoconfirm` to `true` via the Supabase Management API, so a new signup gets an active session immediately rather than requiring an email-confirmation click-through.
**Why**: Default Supabase behavior (`mailer_autoconfirm: false`) requires clicking a confirmation link before a signed-up account can sign in — meaningful friction for solo testing with no SMTP configured. User explicitly chose to trade this off for now.
**Considered**: Leaving email confirmation on to match real production behavior (rejected for now — user is the only tester and this would slow down every test signup with an email round-trip). **Must revisit before inviting any other real user or shipping** — flip `mailer_autoconfirm` back to `false` at that point.

## 2026-07-06 — Grocery list selection stays client-side (no Postgres table)
**Decision**: Which recipes are "on the grocery list" is stored via `UserDefaults` (`GroceryListStoring`/`UserDefaultsGroceryListStore`), not a new Supabase table.
**Why**: Matches the old app's actual behavior exactly — it used `localStorage` for this, not its Postgres backend (confirmed by reading `frontend/src/pages/GroceryList.tsx`). It's a personal, ephemeral UI preference, not shared content, so it doesn't belong in the shared-recipes data model. Ingredients themselves are still fetched live from Supabase per selected recipe and aggregated client-side (summed by case-insensitive name + exact unit match), same algorithm as the old app.
**Considered**: A `grocery_selections` table (rejected — would need RLS just like every other table for zero benefit, since this data has no reason to sync across devices or be queried server-side; UserDefaults is simpler and matches precedent).

## 2026-07-06 — Reminders export uses full access, not write-only
**Decision**: `ReminderService` requests `requestFullAccessToReminders()` rather than iOS 17's more restrictive `requestWriteOnlyAccessToReminders()`.
**Why**: Export needs to find-or-create a "VJ Test Kitchen Groceries" reminders list by name (`store.calendars(for: .reminder)`), which is safer and simpler with read access to existing calendars than working around write-only restrictions on calendar lookup. Low-risk trade-off for a single-user personal app.
**Considered**: Write-only access (more privacy-respecting in principle, rejected for now — adds complexity for calendar lookup with uncertain benefit given this app's single-user context; worth revisiting if this app is ever used by others).

## 2026-07-06 — AI Planner Edge Function scope reduced from the old app
**Decision**: The `ai-chat` Edge Function sends the user's prompt plus an inline recipe catalog (id/title/tags/prep_time/servings) to Gemini and returns plain text. It does **not** carry over the old app's structured-output recipe extraction (`<RECIPE_JSON>`/`<EXISTING_RECIPES>` tags, auto-save-to-database, Gemini context caching for a 15K-recipe catalog).
**Why**: The old app's version is genuinely sophisticated (context caching to avoid re-billing a huge catalog on every message, tagged output parsing to let the AI both recommend existing recipes and propose new ones the user can save with one tap). Replicating all of that is real scope beyond "get AI menu planning working" for a database that currently has a handful of recipes — context caching in particular is solving a scale problem (hundreds of thousands of tokens) this app doesn't have yet. Core chat-based planning against the real recipe catalog is the priority; the richer recipe-extraction UX can come later if/when the catalog grows large enough for caching to matter.
**Considered**: Porting the full old-app behavior now (rejected — meaningfully more complex Edge Function and client-side parsing for a benefit that doesn't apply at current scale).
**Auth model**: recipe reads use a plain `fetch()` to PostgREST with the caller's own forwarded `Authorization` header — RLS applies exactly as it does everywhere else (recipes are shared-readable by any authenticated user). No service_role/admin access is used. Platform-level `verify_jwt = true` (the default) rejects unauthenticated requests before the function code even runs, so the function doesn't need to re-verify the JWT itself.

## 2026-07-06 — ai-chat Edge Function has zero external imports, by necessity
**Decision**: Rewrote `ai-chat` from the CLI's scaffolded `@supabase/server` (`withSupabase`) template to plain `Deno.serve` + built-in `fetch`/`Deno.env` — no `npm:`/`jsr:` specifiers at all.
**Why**: `supabase functions deploy` bundles by running a Docker container (`edge-runtime bundle`) attached to a Supabase-managed network (`supabase_network_<project>`) to resolve remote imports. In this environment that container couldn't resolve DNS at all — verified directly by running a throwaway `alpine` container on that same network and finding it couldn't pull/resolve anything either. Stopping the local dev stack first didn't change this (the network is created independently of `supabase start`). Rather than debug Docker networking further, removing the dependency on remote-import resolution during bundling sidesteps the problem entirely: `Deno.serve`/`Deno.env`/`fetch` are runtime built-ins needing nothing fetched, so there's nothing for the bundler to resolve over a network that may not have egress.
**Considered**: Debugging/fixing the Docker network's internet access (rejected — indeterminate time cost chasing an environment issue, for a fix this codebase doesn't actually need). Using `@supabase/supabase-js` for the recipe-catalog read (rejected once already down the zero-import path — plain PostgREST REST calls are just as correct here and keep the function dependency-free).
**If this recurs**: worth checking `docker network inspect supabase_network_<project>` for driver/IPAM config, and whether Docker Desktop's own network settings (proxy, VPN interaction) are involved — but only if a future Edge Function genuinely needs a package that isn't reasonably avoidable this way.

## 2026-07-06 — Siri via App Intents, no separate Intents extension target

## 2026-07-06 — Siri via App Intents, no separate Intents extension target
**Decision**: `PlanMealIntent` + `VJTestKitchenShortcuts` (`AppShortcutsProvider`) live directly in the main app target and reuse `AIService` as-is.
**Why**: Modern `AppIntents`-based Siri integration (iOS 16+) doesn't require a separate Intents Extension target, a Siri entitlement, or an `NSSiriUsageDescription` privacy key — all of that was specific to the older SiriKit custom-intent (`.intentdefinition`) approach. Running in the main app's process means the intent shares the same signed-in Supabase session already in memory/Keychain, with no Keychain-sharing entitlement needed.
**Known limitation**: if the user isn't signed in, the intent catches the failure and returns a spoken message asking them to open the app and sign in — it doesn't (and can't reasonably) drive the sign-in flow itself from a Siri context.
**Not verified**: real "Hey Siri" voice invocation. Simulator doesn't support the Siri wake word or voice recognition at all — this can only be tested on a real device. Build-time correctness (compiles, matches `AppIntent`/`AppShortcutsProvider` protocols) is what's actually confirmed.
