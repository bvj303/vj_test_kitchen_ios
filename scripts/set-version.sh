#!/usr/bin/env bash
#
# set-version.sh — read or set the app version across every versioned plist.
#
# The marketing version (CFBundleShortVersionString) and build number
# (CFBundleVersion) live as literals in three plists — the iOS app, the macOS
# app, and the embedded iOS widget extension — and Apple REJECTS an upload whose
# embedded extension version differs from its host app's. This script is the one
# place that keeps them in lockstep, so nothing has to remember to bump all three
# by hand.
#
# Usage:
#   scripts/set-version.sh --print                 # show current versions, exit
#   scripts/set-version.sh --bump-build            # CFBundleVersion += 1
#   scripts/set-version.sh --build 42              # set CFBundleVersion = 42
#   scripts/set-version.sh --marketing 1.3         # set CFBundleShortVersionString
#   scripts/set-version.sh --bump-build --marketing 1.3
#
# The build number is read from the FIRST target plist (the iOS app) as the
# source of truth, then written to all of them, so they can't drift.
#
# Target plists default to the three real ones (relative to the repo root, so the
# script works from any CWD). Override by passing explicit plist paths as trailing
# arguments — used by the unit test to operate on throwaway copies.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

print_only=false
bump_build=false
new_build=""
new_marketing=""
plists=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print)      print_only=true; shift ;;
    --bump-build) bump_build=true; shift ;;
    --build)      new_build="${2:?--build needs a value}"; shift 2 ;;
    --marketing)  new_marketing="${2:?--marketing needs a value}"; shift 2 ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "set-version.sh: unknown option '$1'" >&2; exit 2 ;;
    *)            plists+=("$1"); shift ;;
  esac
done

# Default targets if none were passed explicitly.
if [[ ${#plists[@]} -eq 0 ]]; then
  plists=(
    "$REPO_ROOT/VJTestKitchen/Resources/Info.plist"        # iOS app  (source of truth)
    "$REPO_ROOT/VJTestKitchen/Resources/Info-macOS.plist"  # macOS app
    "$REPO_ROOT/VJTestKitchenWidgets/Info.plist"           # embedded widget extension
  )
fi

for p in "${plists[@]}"; do
  [[ -f "$p" ]] || { echo "set-version.sh: no such plist: $p" >&2; exit 1; }
done

read_key() { "$PLIST_BUDDY" -c "Print :$1" "$2"; }
write_key() { "$PLIST_BUDDY" -c "Set :$1 $2" "$3"; }

source_plist="${plists[0]}"
cur_build="$(read_key CFBundleVersion "$source_plist")"
cur_marketing="$(read_key CFBundleShortVersionString "$source_plist")"

if $print_only; then
  echo "marketing (CFBundleShortVersionString): $cur_marketing"
  echo "build     (CFBundleVersion):            $cur_build"
  exit 0
fi

# Resolve the target build number.
if $bump_build && [[ -n "$new_build" ]]; then
  echo "set-version.sh: --bump-build and --build are mutually exclusive" >&2
  exit 2
fi
target_build=""
if [[ -n "$new_build" ]]; then
  [[ "$new_build" =~ ^[0-9]+$ ]] || { echo "set-version.sh: --build must be an integer" >&2; exit 2; }
  target_build="$new_build"
elif $bump_build; then
  [[ "$cur_build" =~ ^[0-9]+$ ]] || { echo "set-version.sh: current build '$cur_build' is not an integer; use --build N" >&2; exit 1; }
  target_build="$(( cur_build + 1 ))"
fi

for p in "${plists[@]}"; do
  [[ -n "$target_build"    ]] && write_key CFBundleVersion            "$target_build"    "$p"
  [[ -n "$new_marketing"   ]] && write_key CFBundleShortVersionString "$new_marketing"   "$p"
done

final_build="${target_build:-$cur_build}"
final_marketing="${new_marketing:-$cur_marketing}"
echo "version set to ${final_marketing} (${final_build}) across ${#plists[@]} plist(s)"
