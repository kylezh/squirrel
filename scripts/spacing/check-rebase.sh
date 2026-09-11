#!/usr/bin/env bash
# Replay committed work in a disposable worktree; never rewrite this checkout.
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
target="${1:-upstream/master}"
git rev-parse --verify "$target^{commit}" >/dev/null
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'Commit your changes first; this check only replays committed patches.' >&2
  exit 1
fi
tmp="$(mktemp -d "${TMPDIR:-/tmp}/squirrel-rebase.XXXXXX")"
cleanup() {
  cd "$root"
  git -C "$tmp/worktree" rebase --abort >/dev/null 2>&1 || true
  git worktree remove --force "$tmp/worktree" >/dev/null 2>&1 || true
  rmdir "$tmp" 2>/dev/null || true
}
trap cleanup EXIT
git worktree add --detach "$tmp/worktree" HEAD >/dev/null
if ! git -C "$tmp/worktree" -c rerere.enabled=false rebase --force-rebase "$target"; then
  echo 'Conflict paths (original checkout untouched):' >&2
  git -C "$tmp/worktree" diff --name-only --diff-filter=U >&2
  exit 1
fi
cd "$tmp/worktree"
mkdir -p build/spacing
swiftc sources/InputSource.swift tests/spacing/InputSourceTests.swift -o build/spacing/input-source-tests
build/spacing/input-source-tests
swiftc sources/InputContinuityTracker.swift tests/spacing/TrackerTests.swift -o build/spacing/tracker-tests
build/spacing/tracker-tests
lua tests/spacing/LuaTests.lua
swiftc sources/InputContinuityTracker.swift sources/InputContextProbe.swift sources/SpacingContext.swift tests/spacing/TextClient.swift tests/spacing/NativeTests.swift -o build/spacing/native-tests
build/spacing/native-tests
printf 'Replay and standalone tests passed on %s. Full app/dependency validation is still required.\n' "$target"
# Return to the owning repository before the EXIT trap removes the worktree.
cd - >/dev/null
