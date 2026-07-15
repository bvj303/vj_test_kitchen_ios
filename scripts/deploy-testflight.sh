#!/usr/bin/env bash
#
# deploy-testflight.sh — archive the iOS app and upload it to TestFlight.
#
# This is the "make it scriptable" replacement for the interactive Xcode
# Organizer → Distribute App → Upload dance. It runs headlessly (no Apple ID
# login prompt, no 2FA) by authenticating with an App Store Connect API key, so
# it works from a laptop, CI, or a background job identically.
#
# ── One-time setup: create an App Store Connect API key ─────────────────────
#   App Store Connect → Users and Access → Integrations → App Store Connect API
#   → generate a key with the "App Manager" role → download the AuthKey_XXXX.p8
#   (you can only download it ONCE) → note the Key ID and the Issuer ID.
#
# ── Provide the credentials (never commit them) ─────────────────────────────
#   Put these in the repo-root .env (gitignored — same place the Supabase CLI
#   secrets live) or export them in your shell / set them as CI secrets:
#     ASC_KEY_ID=XXXXXXXXXX
#     ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#     ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8
#
# ── Run ─────────────────────────────────────────────────────────────────────
#   scripts/deploy-testflight.sh            # bump build, archive, upload
#   scripts/deploy-testflight.sh --check    # validate prerequisites only, no build
#   scripts/deploy-testflight.sh --no-upload      # archive + export .ipa, don't upload
#   scripts/deploy-testflight.sh --build-number 42   # explicit build number (e.g. CI run #)
#   scripts/deploy-testflight.sh --no-bump           # keep the current build number
#
# After a successful upload the build shows up in App Store Connect → TestFlight
# after ~5–15 min of Apple-side processing; add it to a tester group there.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="VJTestKitchen"
PROJECT="$REPO_ROOT/VJTestKitchen.xcodeproj"
BUILD_DIR="$REPO_ROOT/build/testflight"
ARCHIVE_PATH="$BUILD_DIR/VJTestKitchen.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$REPO_ROOT/Config/ExportOptions.plist"

check_only=false
do_upload=true
do_bump=true
explicit_build=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)         check_only=true; shift ;;
    --no-upload)     do_upload=false; shift ;;
    --no-bump)       do_bump=false; shift ;;
    --build-number)  explicit_build="${2:?--build-number needs a value}"; do_bump=false; shift 2 ;;
    --scheme)        SCHEME="${2:?--scheme needs a value}"; shift 2 ;;
    -h|--help)       grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "deploy-testflight.sh: unknown option '$1'" >&2; exit 2 ;;
  esac
done

step() { printf '\n▶︎  %s\n' "$1"; }
fail() { echo "error: $1" >&2; exit 1; }

# ── Load .env (if present) so ASC_* can live there instead of the shell ──────
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a; # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"; set +a
fi

# ── Validate prerequisites ──────────────────────────────────────────────────
step "Checking prerequisites"
[[ "$(uname)" == "Darwin" ]] || fail "TestFlight builds require macOS (xcodebuild)."
command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode."
command -v xcodegen   >/dev/null || fail "xcodegen not found — 'brew install xcodegen'."
[[ -f "$EXPORT_OPTIONS" ]] || fail "missing $EXPORT_OPTIONS"

if $do_upload; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID App Store Connect API Key ID — see the header of this script}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect API Issuer ID)}"
  : "${ASC_KEY_PATH:?set ASC_KEY_PATH (path to AuthKey_XXXX.p8)}"
  [[ -f "$ASC_KEY_PATH" ]] || fail "ASC_KEY_PATH does not exist: $ASC_KEY_PATH"
  # altool discovers the key by ID in a small set of dirs; make sure it's there.
  key_dir="$HOME/.appstoreconnect/private_keys"
  key_dest="$key_dir/AuthKey_${ASC_KEY_ID}.p8"
  if [[ ! -f "$key_dest" ]]; then
    mkdir -p "$key_dir"
    cp "$ASC_KEY_PATH" "$key_dest"
    echo "   copied API key into $key_dir for altool discovery"
  fi
  echo "   App Store Connect API key ${ASC_KEY_ID} ready"
else
  echo "   upload disabled (--no-upload): skipping App Store Connect credential check"
fi
echo "   scheme=$SCHEME  team=89R449GG5Z"

if $check_only; then
  step "Check passed — prerequisites satisfied (no build performed)."
  exit 0
fi

# ── Keep the generated project in sync with project.yml ─────────────────────
step "Regenerating Xcode project (xcodegen)"
( cd "$REPO_ROOT" && xcodegen generate )

# ── Version / build number ──────────────────────────────────────────────────
if [[ -n "$explicit_build" ]]; then
  step "Setting build number to $explicit_build"
  "$REPO_ROOT/scripts/set-version.sh" --build "$explicit_build"
elif $do_bump; then
  step "Bumping build number"
  "$REPO_ROOT/scripts/set-version.sh" --bump-build
else
  step "Keeping current build number (--no-bump)"
fi
"$REPO_ROOT/scripts/set-version.sh" --print

# ── Auth flags shared by archive + export (empty when not uploading) ─────────
auth_flags=()
if $do_upload || [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  auth_flags=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

# ── Archive ─────────────────────────────────────────────────────────────────
step "Archiving $SCHEME (Release, generic/iOS)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  "${auth_flags[@]}"

# ── Export .ipa ─────────────────────────────────────────────────────────────
step "Exporting signed .ipa"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  "${auth_flags[@]}"

ipa="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
[[ -n "$ipa" ]] || fail "no .ipa produced in $EXPORT_DIR"
echo "   exported: $ipa"

if ! $do_upload; then
  step "Done (--no-upload). Inspect the .ipa above; re-run without --no-upload to ship."
  exit 0
fi

# ── Upload to App Store Connect / TestFlight ────────────────────────────────
step "Uploading to App Store Connect (TestFlight)"
xcrun altool --upload-app \
  --type ios \
  --file "$ipa" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

built="$("$REPO_ROOT/scripts/set-version.sh" --print | awk '/build/{print $NF}')"
step "Uploaded ✅  build $built is now processing in App Store Connect."
echo "   It appears under TestFlight in ~5–15 min. Add it to a tester group there."
echo "   Remember to commit the bumped version plists so the build number isn't reused."
