#!/bin/sh
# One-time setup: point git at the tracked hooks in .githooks/ so they run for
# this clone. Run once after cloning:  ./.githooks/install.sh
# (core.hooksPath is local git config and can't be committed, hence this step.)
set -eu
root=$(git rev-parse --show-toplevel)
git -C "$root" config core.hooksPath .githooks
echo "✓ git hooks installed (core.hooksPath = .githooks)."
echo "  project.yml changes will now auto-run 'xcodegen generate' on pull/switch/rebase."
