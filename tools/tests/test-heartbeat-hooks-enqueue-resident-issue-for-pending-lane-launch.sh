#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_HOOKS="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -n "${pending_pid:-}" ]]; then
    kill "${pending_pid}" >/dev/null 2>&1 || true
    wait "${pending_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

skill_root="$tmpdir/skill"
hooks_dir="$skill_root/hooks"
bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
shim_dir="$tmpdir/shim"
capture_file="$tmpdir/capture.log"
state_root="$tmpdir/agent/state"

mkdir -p "$hooks_dir" "$bin_dir" "$assets_dir" "$profile_dir" "$shim_dir" "$state_root/pending-launches"
cp "$REAL_HOOKS" "$hooks_dir/heartbeat-hooks.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/agent"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$tmpdir/agent/runs"
  state_root: "$state_root"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
execution:
  coding_worker: "codex"
  resident_workers:
    issue_reuse_enabled: true
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
  issue_branch_prefix: "agent/demo/issue"
  pr_worktree_branch_prefix: "agent/demo/pr"
EOF

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Resident issue ${issue_id}","body":"Keep going.","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-keep-open"}],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  printf '[]\n'
  exit 0
fi

exit 64
EOF
chmod +x "$shim_dir/gh"

cat >"$bin_dir/agent-project-detached-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_CAPTURE_FILE:?}"
printf 'LAUNCH_MODE=detached\n'
EOF
chmod +x "$bin_dir/agent-project-detached-launch"

(sleep 30) &
pending_pid="$!"
printf '%s\n' "${pending_pid}" >"$state_root/pending-launches/issue-440.pid"

PATH="$shim_dir:$PATH" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_FILE="$capture_file" \
bash -c '
  set -euo pipefail
  source "'"$hooks_dir"'/heartbeat-hooks.sh"
  heartbeat_start_issue_worker 441 >/dev/null
'

test ! -f "$capture_file"
queue_file="$state_root/resident-workers/issue-queue/pending/issue-441.env"
test -f "$queue_file"
grep -q '^ISSUE_ID=441$' "$queue_file"

echo "heartbeat hooks enqueue resident issue for pending lane launch test passed"
