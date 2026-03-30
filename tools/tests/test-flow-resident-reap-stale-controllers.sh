#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLOW_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
state_root="$tmpdir/runtime/demo/state"
controller_dir="$state_root/resident-workers/issues/101"
pending_dir="$state_root/pending-launches"

mkdir -p "$profile_dir" "$controller_dir" "$pending_dir"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$tmpdir/runtime/demo/runs"
  state_root: "$state_root"
  history_root: "$tmpdir/runtime/demo/history"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

printf '%s\n' "$$" >"$pending_dir/issue-101.pid"
cat >"$controller_dir/controller.env" <<EOF
ISSUE_ID=101
CONTROLLER_PID=$$
CONTROLLER_STATE=waiting-due
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
EOF

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  ACP_PROJECT_ID=demo \
  bash -lc '
    source "'"$FLOW_LIB"'"
    flow_resident_issue_reap_stale_state
  '
)"

grep -q '^1$' <<<"$output"
test ! -f "$controller_dir/controller.env"
test ! -f "$pending_dir/issue-101.pid"

echo "flow resident reap stale controllers test passed"
