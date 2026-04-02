#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_PATH="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
mkdir -p "${profile_dir}"

cat >"${profile_dir}/control-plane.yaml" <<'EOF'
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "/tmp/demo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "/tmp/demo-runtime"
  worktree_root: "/tmp/demo-worktrees"
  agent_repo_root: "/tmp/demo"
  runs_root: "/tmp/demo-runtime/runs"
  state_root: "/tmp/demo-runtime/state"
  history_root: "/tmp/demo-runtime/history"
  retained_repo_root: "/tmp/demo"
  vscode_workspace_file: "/tmp/demo.code-workspace"
execution:
  coding_worker: "openclaw"
EOF

output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_ID="demo" \
  bash -c '
    set -euo pipefail
    source "'"${LIB_PATH}"'"
    printf "NO_CYCLE=%s\n" "$(flow_resident_issue_openclaw_session_id "" 441)"
    printf "CYCLE_ONE=%s\n" "$(flow_resident_issue_openclaw_session_id "" 441 1)"
    printf "CYCLE_TWO=%s\n" "$(flow_resident_issue_openclaw_session_id "" 441 2)"
  '
)"

grep -q '^NO_CYCLE=demo-resident-session-issue-441$' <<<"${output}"
grep -q '^CYCLE_ONE=demo-resident-session-issue-441-cycle-1$' <<<"${output}"
grep -q '^CYCLE_TWO=demo-resident-session-issue-441-cycle-2$' <<<"${output}"

echo "resident worker lib openclaw cycle session id test passed"
