#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_LOOP="${FLOW_ROOT}/tools/bin/start-resident-issue-loop.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -n "${controller_pid:-}" ]]; then
    kill "${controller_pid}" >/dev/null 2>&1 || true
    wait "${controller_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

skill_root="$tmpdir/skill"
bin_dir="$skill_root/tools/bin"
hooks_dir="$skill_root/hooks"
assets_dir="$skill_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
shim_dir="$tmpdir/shim"
agent_root="$tmpdir/agent"
repo_root="$tmpdir/repo"
capture_dir="$tmpdir/capture"

mkdir -p "$bin_dir" "$hooks_dir" "$assets_dir" "$profile_dir" "$shim_dir" "$agent_root" "$repo_root" "$capture_dir"
cp "$REAL_LOOP" "$bin_dir/start-resident-issue-loop.sh"
cp "$FLOW_ROOT/tools/bin/resident-issue-controller-lib.sh" "$bin_dir/resident-issue-controller-lib.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$agent_root"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$repo_root"
  runs_root: "$agent_root/runs"
  state_root: "$agent_root/state"
  history_root: "$agent_root/history"
  retained_repo_root: "$repo_root"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
execution:
  coding_worker: "codex"
  resident_workers:
    issue_reuse_enabled: true
    issue_controller_max_immediate_cycles: 2
    controller_poll_seconds: 1
    issue_controller_idle_timeout_seconds: 30
EOF

cat >"$hooks_dir/heartbeat-hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
heartbeat_open_agent_pr_issue_ids() { printf '[]\n'; }
heartbeat_issue_is_heavy() { printf 'no\n'; }
heartbeat_mark_issue_running() { :; }
heartbeat_issue_launch_failed() { :; }
EOF
chmod +x "$hooks_dir/heartbeat-hooks.sh"

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"state":"OPEN","title":"Resident issue ${issue_id}","body":"Keep this issue moving.","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-keep-open"}],"comments":[]}
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

cat >"$shim_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
chmod +x "$shim_dir/tmux"

cat >"$bin_dir/start-issue-worker.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'START:%s\n' "${1:?issue id required}" >>"${TEST_CAPTURE_DIR:?}/events.log"
sleep 2
exit 0
EOF
chmod +x "$bin_dir/start-issue-worker.sh"

cat >"$bin_dir/reconcile-issue-worker.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/reconcile-issue-worker.sh"

FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
PATH="$shim_dir:$PATH" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_DIR="$capture_dir" \
bash "$bin_dir/start-resident-issue-loop.sh" 440 >/dev/null &
controller_pid="$!"

controller_file_440="$agent_root/state/resident-workers/issues/440/controller.env"
for _ in $(seq 1 50); do
  if [[ -f "$controller_file_440" ]] \
    && grep -q '^CONTROLLER_STATE=starting$' "$controller_file_440" \
    && grep -q '^ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-codex-safe$' "$controller_file_440"; then
    break
  fi
  sleep 0.1
done

test -f "$controller_file_440"
grep -q '^CONTROLLER_STATE=starting$' "$controller_file_440"

FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
PATH="$shim_dir:$PATH" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_DIR="$capture_dir" \
bash "$bin_dir/start-resident-issue-loop.sh" 441 >/dev/null

grep -q '^START:440$' "$capture_dir/events.log"
if grep -q '^START:441$' "$capture_dir/events.log"; then
  echo "second controller unexpectedly launched same resident lane while first was still starting" >&2
  exit 1
fi

queue_file="$agent_root/state/resident-workers/issue-queue/pending/issue-441.env"
controller_file_441="$agent_root/state/resident-workers/issues/441/controller.env"

test -f "$queue_file"
grep -q '^ISSUE_ID=441$' "$queue_file"
grep -q '^CONTROLLER_STATE=stopped$' "$controller_file_441"
grep -Eq '^CONTROLLER_REASON=live-lane-controller-440-(starting|launching)$' "$controller_file_441"

echo "start resident issue loop yields to starting live lane controller test passed"
