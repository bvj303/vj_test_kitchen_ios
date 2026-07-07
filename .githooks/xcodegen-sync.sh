#!/bin/sh
# Regenerate the Xcode project when the generated (gitignored)
# VJTestKitchen.xcodeproj has drifted from project.yml *or* from the set of
# source files on disk. Called by the post-merge / post-checkout / post-rewrite
# git hooks so a `git pull`, branch switch, or rebase can't leave you building a
# stale project. See CLAUDE.md ("Regenerate the Xcode project any time
# project.yml changes").
#
# Two drift signals, because they have different tells:
#   1. project.yml *content* changed — detected by mtime: the .xcodeproj is
#      gitignored so git never rewrites it, while git *does* rewrite
#      project.yml's mtime when a checkout/merge changes its content. So
#      "project.yml is newer than the generated project" means a spec change.
#   2. a source file was *added / renamed / removed* — this never touches
#      project.yml (xcodegen picks sources up by glob), so mtime can't see it.
#      Instead compare the tracked *.swift set against what the generated
#      project references; a tracked source the project doesn't know about (the
#      classic "cannot find <NewType>" build break after pulling a new file)
#      forces a regen.
set -eu

root=$(git rev-parse --show-toplevel)
spec="$root/project.yml"
pbxproj="$root/VJTestKitchen.xcodeproj/project.pbxproj"

# No spec, nothing to do.
[ -f "$spec" ] || exit 0

needs_regen=no
reason=""

if [ ! -f "$pbxproj" ]; then
  needs_regen=yes
  reason="no generated project yet"
elif [ "$spec" -nt "$pbxproj" ]; then
  needs_regen=yes
  reason="project.yml changed"
else
  # Basenames of *.swift the generated project currently references…
  proj_refs=$(grep -oE '[A-Za-z0-9_+.-]+\.swift' "$pbxproj" 2>/dev/null | sed 's#.*/##' | sort -u)
  # …vs. every tracked *.swift source. A source missing from the project means
  # a new/renamed file the stale project would fail to compile against.
  for f in $(cd "$root" && git ls-files '*.swift' | sed 's#.*/##' | sort -u); do
    if ! printf '%s\n' "$proj_refs" | grep -qxF "$f"; then
      needs_regen=yes
      reason="source file $f is not in the generated project"
      break
    fi
  done
fi

[ "$needs_regen" = yes ] || exit 0

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "⚠︎  $reason but xcodegen isn't installed."
  echo "    Install it (brew install xcodegen) and run 'xcodegen generate' before building."
  exit 0
fi

echo "▶︎  $reason — running 'xcodegen generate'…"
( cd "$root" && xcodegen generate )
