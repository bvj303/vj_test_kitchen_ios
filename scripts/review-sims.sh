#!/usr/bin/env bash
#
# review-sims.sh — build the app once and launch it on both an iPhone and an
# iPad simulator, so a completed feature can be reviewed in-app across both
# form factors (compact iPhone + regular/split-view iPad).
#
# Usage:
#   scripts/review-sims.sh                 # default scheme + devices
#   REVIEW_IPHONE="iPhone 17" REVIEW_IPAD="iPad Air 13-inch (M4)" scripts/review-sims.sh
#
# Env overrides:
#   REVIEW_SCHEME   Xcode scheme      (default: VJTestKitchen)
#   REVIEW_IPHONE   iPhone sim name   (default: iPhone 17 Pro Max)
#   REVIEW_IPAD     iPad sim name     (default: iPad Pro 13-inch (M5))
#
set -euo pipefail

SCHEME="${REVIEW_SCHEME:-VJTestKitchen}"
IPHONE_NAME="${REVIEW_IPHONE:-iPhone 17 Pro Max}"
IPAD_NAME="${REVIEW_IPAD:-iPad Pro 13-inch (M5)}"
BUNDLE_ID="com.bvj303.vjtestkitchen"

cd "$(dirname "$0")/.."

# Resolve a simulator UDID by device name (first available match) and boot it.
resolve_and_boot() {
  local name="$1" udid
  udid=$(xcrun simctl list devices available \
    | grep -F "$name (" | head -1 \
    | grep -oiE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
  if [ -z "$udid" ]; then
    echo "error: no available simulator named '$name'" >&2
    echo "       set REVIEW_IPHONE / REVIEW_IPAD to a name from 'xcrun simctl list devices'" >&2
    return 1
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true   # already-booted is fine
  printf '%s' "$udid"
}

echo "▸ Resolving simulators…"
IPHONE_ID=$(resolve_and_boot "$IPHONE_NAME")
IPAD_ID=$(resolve_and_boot "$IPAD_NAME")
open -a Simulator || true

# Where the built .app will land for the simulator SDK (parsed, not guessed).
APP_DIR=$(xcodebuild -scheme "$SCHEME" -destination "id=$IPHONE_ID" -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/ TARGET_BUILD_DIR / {d=$2} / FULL_PRODUCT_NAME / {n=$2} END {print d"/"n}')

echo "▸ Building ${SCHEME}…"
xcodebuild -scheme "$SCHEME" -destination "id=$IPHONE_ID" build >/dev/null

if [ ! -d "$APP_DIR" ]; then
  echo "error: built app not found at $APP_DIR" >&2
  exit 1
fi

# The app is universal, so one build installs on both device types.
for id in "$IPHONE_ID" "$IPAD_ID"; do
  name=$(xcrun simctl list devices | grep -F "$id" | sed -E 's/ *\(.*//' | xargs)
  echo "▸ Launching on ${name}…"
  xcrun simctl install "$id" "$APP_DIR"
  xcrun simctl terminate "$id" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$id" "$BUNDLE_ID" >/dev/null
done

echo "✓ Launched on iPhone + iPad for review."
