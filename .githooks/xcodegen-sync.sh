#!/bin/sh
# Regenerate the Xcode project when project.yml has drifted ahead of the
# generated (gitignored) VJTestKitchen.xcodeproj. Called by the post-merge /
# post-checkout / post-rewrite git hooks so a `git pull`, branch switch, or
# rebase that touches project.yml can't leave you building a stale project
# (e.g. the dangling CODE_SIGN_ENTITLEMENTS reference after the WeatherKit
# removal). See CLAUDE.md ("Regenerate the Xcode project any time project.yml
# changes").
#
# Detection is purely by modification time: the .xcodeproj is gitignored, so
# git never rewrites it, while git *does* rewrite project.yml's mtime whenever
# a checkout/merge changes its content. So "project.yml is newer than the
# generated project" is true exactly when regeneration is actually needed.
set -eu

root=$(git rev-parse --show-toplevel)
spec="$root/project.yml"
pbxproj="$root/VJTestKitchen.xcodeproj/project.pbxproj"

# No spec, nothing to do.
[ -f "$spec" ] || exit 0

# Up to date already? (project exists and is at least as new as the spec.)
if [ -f "$pbxproj" ] && [ ! "$spec" -nt "$pbxproj" ]; then
  exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "⚠︎  project.yml changed but xcodegen isn't installed."
  echo "    Install it (brew install xcodegen) and run 'xcodegen generate' before building."
  exit 0
fi

echo "▶︎  project.yml changed — running 'xcodegen generate'…"
( cd "$root" && xcodegen generate )
