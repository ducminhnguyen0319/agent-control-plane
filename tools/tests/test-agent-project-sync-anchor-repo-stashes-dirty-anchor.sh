#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_ANCHOR_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-sync-anchor-repo"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

origin_root="$tmpdir/origin.git"
canonical_root="$tmpdir/canonical"
anchor_root="$tmpdir/anchor"
extra_worktree="$tmpdir/worktrees/issue-3"

git init --bare "$origin_root" >/dev/null 2>&1
git clone "$origin_root" "$canonical_root" >/dev/null 2>&1
git -C "$canonical_root" config user.name "Test"
git -C "$canonical_root" config user.email "test@example.com"
printf 'seed\n' >"$canonical_root/README.md"
git -C "$canonical_root" add README.md
git -C "$canonical_root" commit -m "init" >/dev/null 2>&1
git -C "$canonical_root" push origin HEAD:main >/dev/null 2>&1
git -C "$canonical_root" checkout main >/dev/null 2>&1

git clone --branch main "$origin_root" "$anchor_root" >/dev/null 2>&1
git -C "$anchor_root" config user.name "Test"
git -C "$anchor_root" config user.email "test@example.com"
git -C "$anchor_root" checkout -b pr-5-review >/dev/null 2>&1
printf 'dirty change\n' >>"$anchor_root/README.md"

mkdir -p "$(dirname "$extra_worktree")"
git -C "$anchor_root" worktree add -b issue-3 "$extra_worktree" origin/main >/dev/null 2>&1

sync_output="$(
  bash "$SYNC_ANCHOR_SCRIPT" \
    --canonical-root "$canonical_root" \
    --anchor-root "$anchor_root" \
    --remote origin \
    --default-branch main
)"

grep -q '^DIRTY_STATE_STASHED=yes$' <<<"$sync_output"
grep -q '^DIRTY_STASH_MESSAGE=acp-anchor-sync-' <<<"$sync_output"
test "$(git -C "$anchor_root" branch --show-current)" = "main"
test -z "$(git -C "$anchor_root" status --short --untracked-files=no)"
git -C "$anchor_root" stash list | grep -q 'acp-anchor-sync-'
test -d "$extra_worktree"
git -C "$extra_worktree" status --short >/dev/null

echo "agent-project-sync-anchor-repo stashes dirty anchor test passed"
