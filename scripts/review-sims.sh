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

# Resolve a simulator UDID by device name and boot it. When the same name
# exists on several runtimes (e.g. iOS 26.5 and 27.0), take the NEWEST — the
# first listed can be a runtime older than the app's deployment target, which
# made the build-settings query below fail.
resolve_and_boot() {
  local name="$1" udid
  udid=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = [int(x) for x in runtime.rsplit(".iOS-", 1)[1].split("-")]
    for d in devices:
        if d["name"] == name and (best is None or version > best[0]):
            best = (version, d["udid"])
print(best[1] if best else "")
' "$name")
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
# Show the booted devices. Xcode 27.1 replaced Simulator.app with Device Hub.
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [ -d "$DEV_DIR/Applications/Simulator.app" ]; then
  open -a "$DEV_DIR/Applications/Simulator.app" || true
elif [ -d "$DEV_DIR/../Applications/DeviceHub.app" ]; then
  open -a "$DEV_DIR/../Applications/DeviceHub.app" || true
else
  open -a Simulator 2>/dev/null || true
fi

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
