# Runbook

Operational reference for VJ Test Kitchen (iOS/macOS) — how to **run, build, test, deploy**, and manage **environments**. Architecture and the *why* behind decisions live in [`CLAUDE.md`](CLAUDE.md) and [`DECISIONS.md`](DECISIONS.md); this file is the *how*.

- **Supabase (prod)**: ref `aviyhrmjsqygoyzjprii`, region `us-east-2`, Postgres 17.
- **Schemes**: `VJTestKitchen` (iOS/iPadOS), `VJTestKitchenMac` (macOS). Both build from one shared source tree.
- **Bundle id**: `com.bvj303.vjtestkitchen`.

---

## First-time setup (per clone)

```bash
# 1. Install the git hooks that keep the generated .xcodeproj in sync with project.yml
./.githooks/install.sh

# 2. Client secrets (gitignored). Fill in the real Supabase URL + publishable key
#    from Dashboard → Settings → API. Note the https:/$()/ escaping in the file.
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig

# 3. Generate the Xcode project (it's gitignored — always regenerated from project.yml)
xcodegen generate

# 4. Open and build
open VJTestKitchen.xcodeproj
```

**Tooling:** Xcode **26+**, [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), the [Supabase CLI](https://supabase.com/docs/guides/cli) (`SUPABASE_ACCESS_TOKEN` in your shell profile), and [Deno](https://deno.com) for the Edge Functions.

> The `.xcodeproj` is gitignored and regenerated from `project.yml`. The git hooks regenerate it after a pull/checkout/rebase, and an Xcode pre-build guard fails the build if `project.yml` is newer than the generated project. If you ever see "cannot find `<Type>` in scope" after a branch switch, run `xcodegen generate`.

---

## Run

- **Simulator / device**: pick the `VJTestKitchen` or `VJTestKitchenMac` scheme in Xcode and Run.
- **Both form factors at once** (the standard review step after a feature):
  ```bash
  scripts/review-sims.sh          # builds once, installs + launches on a booted iPhone + iPad sim
  # Device names override via REVIEW_IPHONE / REVIEW_IPAD env vars.
  ```

---

## Test

Unit tests use **Swift Testing** (`@Test`/`#expect`), not XCTest.

```bash
# iOS
xcodebuild test -scheme VJTestKitchen \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# macOS
xcodebuild test -scheme VJTestKitchenMac -destination 'platform=macOS'

# Edge Functions (Deno)
deno test --allow-net supabase/functions/
deno check supabase/functions/ai-chat/index.ts supabase/functions/delete-account/index.ts
```

Follow the TDD lifecycle (red → green → refactor) — see `CLAUDE.md`.

---

## Continuous Integration

`.github/workflows/ci.yml` runs the suite as a **merge gate** on PRs to `main` (and on pushes to `main`):

| Job | What it runs | Runner |
|---|---|---|
| iOS build & unit tests | `xcodegen generate` → download iOS 26 sim runtime → `xcodebuild test` | `macos-26` |
| macOS build & unit tests | `xcodebuild test` (VJTestKitchenMac) | `macos-26` |
| Edge Function checks | `deno check` + `deno test --allow-net` | `ubuntu-latest` |

- CI seeds **placeholder** secrets from `Secrets.xcconfig.example` — no GitHub secrets needed for CI (the unhosted unit tests inject their own bundle).
- The `macos-26` image ships Xcode 26 but **not** the iOS 26 simulator runtime, so the iOS job downloads it (`xcodebuild -downloadPlatform iOS`).
- **Watch a run**: `gh pr checks <pr#> --watch`; on failure, `gh run view <run-id> --log-failed`.
- **Make it enforced**: GitHub → Settings → Branches → branch-protection rule on `main` → "Require status checks to pass" → select the three checks.

---

## Environments

Two Supabase projects: **prod** (ships to TestFlight/App Store) and **staging** (dev/simulator). Credentials are kept separate per environment on purpose — a dev run must never read or mutate prod data or burn prod quota.

- Client wiring lives in `project.yml` under `configFiles`, one xcconfig per build config:
  - **Release** → `Config/Secrets.xcconfig` (prod)
  - **Debug** → `Config/Secrets.staging.xcconfig` (staging), once activated
- Both files are gitignored; only the `*.example` templates are tracked.

### Activating staging (one-time)

1. **Create the project** — Dashboard → New project: `vjtk-staging`, region `us-east-2`, Postgres 17. Save the DB password; note the ref (`<STAGING_REF>`).
2. **Apply the schema** (migrations carry schema + RLS + the `avatars` storage bucket), without disturbing the prod link:
   ```bash
   supabase db push --db-url "postgresql://postgres:<PASSWORD>@db.<STAGING_REF>.supabase.co:5432/postgres"
   ```
3. **Deploy the functions:**
   ```bash
   supabase functions deploy ai-chat        --project-ref <STAGING_REF>
   supabase functions deploy delete-account  --project-ref <STAGING_REF>
   ```
4. **Set function secrets** (`service_role` is auto-injected — don't set it):
   ```bash
   supabase secrets set GEMINI_API_KEY=<KEY> --project-ref <STAGING_REF>
   ```
5. **Mirror auth settings** in the staging dashboard. Tip: staging can keep email autoconfirm **on** for fast test signups while prod requires confirmation.
6. **Fill in the client file:**
   ```bash
   cp Config/Secrets.staging.xcconfig.example Config/Secrets.staging.xcconfig
   # edit → SUPABASE_URL / SUPABASE_ANON_KEY for the staging project (mind the https:/$()/ escaping)
   ```
7. **Flip the build config** in `project.yml`, then `xcodegen generate`:
   ```yaml
   configFiles:
     Debug:   Config/Secrets.staging.xcconfig   # dev / simulator → staging
     Release: Config/Secrets.xcconfig           # TestFlight / App Store → prod
   ```
8. **Verify**: a Debug build signs up a throwaway user → it lands in **staging** Auth, not prod. A Release build still points at prod.

> Debug→staging means simulator builds hit **remote staging**. To develop against the **local** `supabase start` stack instead, that's a separate xcconfig pointing at `127.0.0.1` — don't overload the staging file for it.

---

## Observability

Crash reporting and structured logging live in `VJTestKitchen/Services/Observability/`.

- **Logging**: use `AppLogger.shared` — `.debug/.info/.notice/.warning/.error/.fault(_, category:, metadata:)`. Everything goes to `os.Logger` (subsystem = bundle id, category = the `category:` you pass), so it's retrievable without a debugger:
  ```bash
  # Live stream (iOS Simulator or a booted device), filtered to this app:
  xcrun simctl spawn booted log stream --level debug \
    --predicate 'subsystem == "com.bvj303.vjtestkitchen"'
  # macOS: same, without simctl —
  log stream --level debug --predicate 'subsystem == "com.bvj303.vjtestkitchen"'
  ```
- **Remote error logs**: `.error`/`.fault` events are also inserted into the private `client_logs` Supabase table (per-user, RLS-enforced) via `RemoteLogSink`. Query a user's recent errors from the SQL editor / psql:
  ```sql
  select created_at, level, category, message, metadata, platform, app_version
  from public.client_logs order by created_at desc limit 50;
  ```
  Best-effort by design: it silently no-ops when signed out or when Supabase isn't configured, and never throws. **Requires the `client_logs` migration to be applied to the target project** (see the push note under Deploy) — until then remote logging is a no-op.
- **Crashes/hangs**: `CrashReporter` (MetricKit) is started in `VJTestKitchenApp.init`. MetricKit **batches** diagnostics and delivers them on a *later* launch (a crash can arrive up to ~24h afterward), where they're logged at `.fault`/`.error` and persisted like any other error event — so it's after-the-fact diagnostics, not live alerting. To force a delivery while testing on a device: Settings → Developer → (MetricKit) or wait for the next-day cycle; the Simulator does not deliver real crash payloads.

---

## Continuous Deployment

`.github/workflows/deploy.yml` deploys the **backend** (Edge Functions + DB migrations) from the pipeline, not a laptop. Both actions are idempotent, so re-runs are safe.

> **Live since 2026-07-15.** The three secrets are set and the **staging** path is verified — the first merge to `main` deployed the Edge Functions + ran `db push` against staging, green end-to-end. The **prod** path awaits the one-time `production` environment setup (below) plus a first `v*` tag.

| Target | Trigger | What deploys |
|---|---|---|
| **staging** (`gmqjhffdtsrpkwrygimz`) | **automatic** on every push/merge to `main` | `functions deploy ai-chat` + `delete-account`, then `db push` |
| **production** (`aviyhrmjsqygoyzjprii`) | a **release tag** `v*` (or a manual `workflow_dispatch`), **gated** by the `production` Environment's required-reviewer rule | same two steps against prod |

- **Ship a release to prod**: `git tag v1.3 && git push origin v1.3` → the run pauses on the `production` environment for a one-click approval, then deploys. Manual re-run: Actions → Deploy → *Run workflow* → pick `production`.
- **Required GitHub secrets** (Settings → Secrets and variables → Actions):
  | Secret | Value |
  |---|---|
  | `SUPABASE_ACCESS_TOKEN` | Personal access token (Dashboard → Account → Access Tokens) |
  | `STAGING_DB_URL` | Full **session-pooler** URL incl. password (Dashboard → Connect → Session pooler). The direct `db.<ref>.supabase.co` host is IPv6-only; GitHub runners are IPv4, so CI must use the IPv4 pooler. |
  | `PROD_DB_URL` | Same, for prod |

  Project refs are non-secret and live as `env` in the workflow.
- **One-time gate setup**: Settings → Environments → **New environment** `production` → add a **Required reviewers** protection rule (yourself). Without it, a tag push would deploy prod unattended. (A `staging` environment is referenced too, for deployment tracking — no protection rule needed there.)
- The `pgdelta … certificate` line `db push` may print at the end is **cosmetic** (the migration still applies); the `Verify remote migration history` step (`migration list`) is the source of truth.
- **Not yet automated**: the client (TestFlight / App Store) upload — see below.

## Deploy (manual / local)

The pipeline above is the normal path. Run these by hand only for a hotfix from a laptop or when reproducing a CD step locally.

### Backend (Supabase)

> **`client_logs` (`20260714010000`)** has been pushed to **both prod and staging** (2026-07-14) and verified live. Note: applying it revealed staging was actually **empty** (its earlier "activation" never took effect), so the same push brought staging to full schema parity with prod — all 15 migrations now recorded there.

```bash
# Database migrations → prod (gated; confirm before pushing to prod)
supabase db push

# Edge Functions → prod
supabase functions deploy ai-chat
supabase functions deploy delete-account
```

- **Server secrets** (`GEMINI_API_KEY`, and `service_role` bypasses RLS) live **only** as Supabase secrets — never in the client, `.env`, or git:
  ```bash
  supabase secrets set GEMINI_API_KEY=<KEY> --project-ref <REF>
  ```
- **Ship order gotcha**: the client sends `messages` to `ai-chat` and uses the atomic `save_recipe` RPC — deploy the function and `db push` the migration **before/with** any client release, or those paths 4xx against the deployed backend.

### Client (TestFlight / App Store)

Distribution signing (Mac App Store / Developer ID / App Store Connect) is not yet automated. For local device builds and the current signing setup, see `CLAUDE.md` and the device-signing notes. Archive the `VJTestKitchen` scheme (Release → prod) and upload via Xcode Organizer / `xcodebuild archive` + `xcrun altool`/`notarytool` when that step is set up.

---

## Backup & restore

Two layers of safety net for the Postgres data:

1. **Managed (Supabase platform).** On the paid plans, Supabase takes **daily automated backups** (Dashboard → Database → Backups, ~7-day retention; Point-in-Time Recovery is a paid add-on). On the **Free plan there are no automated backups** — the logical dump below *is* the backup, so run it on a cadence you're comfortable losing data back to.
2. **Logical dump (plan-independent — what we actually rely on).** `supabase db dump` against the IPv4 **session-pooler** URL (same host the CD pipeline uses; the direct `db.<ref>` host is IPv6-only). Passwords come from the gitignored `.env`, never the command line history in plaintext.

> Dumps can contain **user data** — they're written to the gitignored `backups/` directory and must **never** be committed.

### Take a backup (prod)

```bash
source .env
PROD_URL="postgresql://postgres.aviyhrmjsqygoyzjprii:$(python3 -c "import urllib.parse,os;print(urllib.parse.quote(os.environ['SUPABASE_DB_PASSWORD'],safe=''))")@aws-1-us-east-2.pooler.supabase.com:5432/postgres"
mkdir -p backups
supabase db dump --db-url "$PROD_URL"             -f backups/prod-schema-$(date +%F).sql   # schema (DDL)
supabase db dump --db-url "$PROD_URL" --data-only -f backups/prod-data-$(date +%F).sql     # data
```

`supabase db dump` covers the **`public`** schema by default — i.e. app data (recipes, meal_plans, grocery_items, profiles, client_logs…). It does **not** dump the `auth` schema, so **user accounts (`auth.users`) are not included**; the restore below repopulates app data, not identities. (A full-identity clone would need a separate `auth`-schema dump and is out of scope for the app-data drill.)

### Restore drill: prod → staging

The engineering-principles "test a restore *before* you need it" exercise. Prod → **staging** is the target: staging is the throwaway environment (Debug builds point at it), so a restore there is low-stakes *and* doubles as seeding the simulator with realistic data. **This overwrites staging's data — never run it in reverse.**

```bash
STAGING_URL="postgresql://postgres.gmqjhffdtsrpkwrygimz:$(python3 -c "import urllib.parse,os;print(urllib.parse.quote(os.environ['SUPABASE_STAGING_DB_PASSWORD'],safe=''))")@aws-1-us-west-2.pooler.supabase.com:5432/postgres"

# 1. Staging schema must already match prod (all migrations applied). If prod has
#    a newer migration, push it to staging first — the CD pipeline does this on
#    merge, or manually: supabase db push --db-url "$STAGING_URL" --yes
# 2. Load prod's data into staging's matching schema:
psql "$STAGING_URL" -f backups/prod-data-<date>.sql
```

If staging is **not** empty, existing rows will collide on primary keys — reset it first (`supabase db reset` locally, or truncate the public tables on staging) so the drill is repeatable.

### Verify the restore

- **Row counts match prod** for a spot-check table:
  `psql "$STAGING_URL" -c "select count(*) from recipes;"` vs. the same against `$PROD_URL`.
- **RLS is still enforced** — a `set role authenticated` + `set_config('request.jwt.claims', …)` query sees only its own rows (see the psql role-simulation in `DECISIONS.md`).
- **The app reads it** — a Debug build (→ staging) opens and shows the restored catalog/plans.

> **Status:** procedure documented; the live drill has **not been run yet** (deferred to a hands-on session, since it reads prod and overwrites staging). Record the first successful run's output + timings in `DECISIONS.md` when done.

---

## Common tasks

| Task | Command |
|---|---|
| Regenerate Xcode project | `xcodegen generate` |
| Reset local Supabase + reapply migrations | `supabase db reset` |
| Import ATK test recipes | `python3 scripts/import_atk_recipes.py --limit 250` (see `CLAUDE.md` for flags) |
| Re-render app icons | `swift scripts/render_app_icon.swift VJTestKitchen/Resources/Assets.xcassets` |
| Launch on both sims for review | `scripts/review-sims.sh` |
