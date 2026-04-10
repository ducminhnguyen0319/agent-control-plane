#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_LOOP="${FLOW_ROOT}/tools/bin/start-resident-issue-loop.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

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
  coding_worker: "openclaw"
  resident_workers:
    issue_reuse_enabled: true
    issue_controller_max_immediate_cycles: 1
    controller_poll_seconds: 1
    issue_controller_idle_timeout_seconds: 1
EOF

cat >"$hooks_dir/heartbeat-hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

heartbeat_open_agent_pr_issue_ids() {
  local count_file="${TEST_CAPTURE_DIR:?}/start-count.txt"
  local count="0"
  if [[ -f "${count_file}" ]]; then
    count="$(cat "${count_file}")"
  fi
  if [[ "${count}" =~ ^[1-9][0-9]*$ ]]; then
    printf '["440"]\n'
  else
    printf '[]\n'
  fi
}
heartbeat_list_ready_issue_ids() { :; }
heartbeat_issue_is_recurring() {
  case "${1:-}" in
    440|441) printf 'yes\n' ;;
    *) printf 'no\n' ;;
  esac
}
heartbeat_issue_is_scheduled() { printf 'no\n'; }
heartbeat_issue_is_heavy() { printf 'no\n'; }
heartbeat_mark_issue_running() {
  printf 'RUNNING:%s:%s\n' "${1:?issue id required}" "${2:-no}" >>"${TEST_CAPTURE_DIR:?}/events.log"
}
heartbeat_issue_launch_failed() {
  printf 'FAILED:%s\n' "${1:?issue id required}" >>"${TEST_CAPTURE_DIR:?}/events.log"
}
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

if [[ "${1:-}" == "has-session" ]]; then
  pid_file="${TEST_CAPTURE_DIR:?}/tmux-session.pid"
  if [[ -f "${pid_file}" ]]; then
    pid="$(tr -d '[:space:]' <"${pid_file}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      exit 0
    fi
    rm -f "${pid_file}"
  fi
  exit 1
fi

exit 1
EOF
chmod +x "$shim_dir/tmux"

cat >"$bin_dir/start-issue-worker.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

issue_id="${1:?issue id required}"
capture_dir="${TEST_CAPTURE_DIR:?}"
count_file="${capture_dir}/start-count.txt"
count="0"
if [[ -f "${count_file}" ]]; then
  count="$(cat "${count_file}")"
fi
count="$((count + 1))"
printf '%s\n' "${count}" >"${count_file}"
printf 'START:%s:%s\n' "${issue_id}" "${count}" >>"${capture_dir}/events.log"
(sleep 0.2) &
printf '%s\n' "$!" >"${capture_dir}/tmux-session.pid"
EOF
chmod +x "$bin_dir/start-issue-worker.sh"

cat >"$bin_dir/reconcile-issue-worker.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'RECONCILE:%s\n' "${1:?session required}" >>"${TEST_CAPTURE_DIR:?}/events.log"
EOF
chmod +x "$bin_dir/reconcile-issue-worker.sh"

queue_dir="$agent_root/state/resident-workers/issue-queue/pending"
mkdir -p "$queue_dir"
cat >"$queue_dir/issue-441.env" <<'EOF'
ISSUE_ID=441
QUEUED_BY=test
QUEUED_AT=2026-03-26T00:00:00Z
EOF

FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
PATH="$shim_dir:$PATH" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_DIR="$capture_dir" \
bash "$bin_dir/start-resident-issue-loop.sh" 440 >/dev/null

controller_dir="$agent_root/state/resident-workers/issues"
controller_file_441="$controller_dir/441/controller.env"

grep -q '^2$' "$capture_dir/start-count.txt"
grep -q '^START:440:1$' "$capture_dir/events.log"
grep -q '^START:441:2$' "$capture_dir/events.log"
grep -q '^RECONCILE:demo-issue-441$' "$capture_dir/events.log"
test ! -f "$queue_dir/issue-441.env"
test -f "$controller_file_441"
grep -q '^ISSUE_ID=441$' "$controller_file_441"
grep -q '^CONTROLLER_REASON=idle-timeout$' "$controller_file_441"

echo "start resident issue loop consumes queued lease test passed"
