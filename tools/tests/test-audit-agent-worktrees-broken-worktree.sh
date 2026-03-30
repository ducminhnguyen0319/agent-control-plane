#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_SCRIPT="${FLOW_ROOT}/tools/bin/audit-agent-worktrees.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
agent_root="$tmpdir/agent"

mkdir -p "$repo_root" "$worktree_root" "$agent_root/runs"
repo_root="$(cd "$repo_root" && pwd -P)"
worktree_root="$(cd "$worktree_root" && pwd -P)"
agent_root="$(cd "$agent_root" && pwd -P)"

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Codex"
git -C "$repo_root" config user.email "codex@example.com"
printf 'root\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1

broken_branch="agent/alpha/issue-360-broken-test"
broken_worktree="$worktree_root/issue-360-broken-test"
git -C "$repo_root" worktree add -b "$broken_branch" "$broken_worktree" main >/dev/null 2>&1
rm -f "$broken_worktree/.git"

output="$(
  F_LOSNING_AGENT_REPO_ROOT="$repo_root" \
  F_LOSNING_WORKTREE_ROOT="$worktree_root" \
  F_LOSNING_AGENT_ROOT="$agent_root" \
  bash "$AUDIT_SCRIPT" --cleanup
)"

grep -q '^BROKEN_WORKTREE=yes$' <<<"$output"
grep -q '^CLEANUP=removed$' <<<"$output"
grep -q '^LEGACY_AGENT_WORKTREE_CLEANED=1$' <<<"$output"
test ! -e "$broken_worktree"

echo "audit agent worktrees broken-worktree cleanup test passed"
