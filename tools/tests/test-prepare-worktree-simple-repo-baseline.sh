#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREPARE_BIN="${FLOW_ROOT}/tools/bin/prepare-worktree.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktree"

mkdir -p "$profile_dir" "$repo_root/node_modules"
mkdir -p "$worktree_root"

cat >"$repo_root/package.json" <<'EOF'
{
  "name": "demo-repo",
  "private": true
}
EOF

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Codex"
git -C "$repo_root" config user.email "codex@example.com"
git -C "$worktree_root" init -b main >/dev/null 2>&1
git -C "$worktree_root" config user.name "Codex"
git -C "$worktree_root" config user.email "codex@example.com"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$repo_root"
  runs_root: "$tmpdir/runtime/demo/runs"
  state_root: "$tmpdir/runtime/demo/state"
  history_root: "$tmpdir/runtime/demo/history"
  retained_repo_root: "$repo_root"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  ACP_PROJECT_ID=demo \
  ACP_SYNC_DEPENDENCY_BASELINE_SCRIPT=/nonexistent \
  bash "$PREPARE_BIN" "$worktree_root"
)"

grep -q "^WORKTREE=${worktree_root}\$" <<<"$output"
grep -q "^SANDBOX_ARTIFACT_DIR=${worktree_root}/.openclaw-artifacts\$" <<<"$output"
test -L "$worktree_root/node_modules"

echo "prepare worktree simple repo baseline test passed"
