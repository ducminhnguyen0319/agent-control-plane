#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_LOOP="${FLOW_ROOT}/tools/bin/start-resident-issue-loop.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
REAL_PROVIDER_STATE="${FLOW_ROOT}/tools/bin/provider-cooldown-state.sh"
REAL_RETRY_STATE="${FLOW_ROOT}/tools/bin/agent-project-retry-state"

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
state_root="$agent_root/state"
primary_meta_file="$state_root/resident-workers/issues/issue-lane-recurring-general-openclaw-safe/metadata.env"
fallback_meta_file="$state_root/resident-workers/issues/issue-lane-recurring-general-claude-safe/metadata.env"
primary_cooldown_file="$state_root/retries/providers/openclaw-primary-model.env"

mkdir -p "$bin_dir" "$hooks_dir" "$assets_dir" "$profile_dir" "$shim_dir" "$agent_root" "$repo_root" "$capture_dir"
cp "$REAL_LOOP" "$bin_dir/start-resident-issue-loop.sh"
cp "$FLOW_ROOT/tools/bin/resident-issue-controller-lib.sh" "$bin_dir/resident-issue-controller-lib.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
cp "$REAL_PROVIDER_STATE" "$bin_dir/provider-cooldown-state.sh"
cp "$REAL_RETRY_STATE" "$bin_dir/agent-project-retry-state"
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
  state_root: "$state_root"
  history_root: "$agent_root/history"
  retained_repo_root: "$repo_root"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
execution:
  coding_worker: "openclaw"
  provider_quota:
    cooldowns: "300,900"
  provider_pool_order: "primary fallback"
  provider_pools:
    primary:
      coding_worker: "openclaw"
      openclaw:
        model: "primary/model"
        thinking: "adaptive"
        timeout_seconds: 321
    fallback:
      coding_worker: "claude"
      claude:
        model: "fallback-sonnet"
        permission_mode: "dontAsk"
        effort: "high"
        timeout_seconds: 777
        max_attempts: 5
        retry_backoff_seconds: 12
  resident_workers:
    issue_reuse_enabled: true
    issue_controller_max_immediate_cycles: 2
    controller_poll_seconds: 1
    issue_controller_idle_timeout_seconds: 1
EOF

cat >"$hooks_dir/heartbeat-hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
heartbeat_open_agent_pr_issue_ids() { printf '[]\n'; }
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
printf 'START:%s:%s:%s\n' "${issue_id}" "${count}" "${ACP_CODING_WORKER:-}" >>"${capture_dir}/events.log"
(sleep 0.2) &
printf '%s\n' "$!" >"${capture_dir}/tmux-session.pid"
EOF
chmod +x "$bin_dir/start-issue-worker.sh"

cat >"$bin_dir/reconcile-issue-worker.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

session="\${1:?session required}"
capture_dir="${capture_dir}"
count_file="\${capture_dir}/reconcile-count.txt"
count="0"
if [[ -f "\${count_file}" ]]; then
  count="\$(cat "\${count_file}")"
fi
count="\$((count + 1))"
printf '%s\n' "\${count}" >"\${count_file}"
printf 'RECONCILE:%s:%s\n' "\${session}" "\${count}" >>"\${capture_dir}/events.log"

mkdir -p "$(dirname "$primary_meta_file")" "$(dirname "$fallback_meta_file")" "$(dirname "$primary_cooldown_file")"
if [[ "\${count}" == "1" ]]; then
  cat >"$primary_meta_file" <<'OUT'
LAST_FAILURE_REASON=provider-quota-limit
OUT
  future_epoch=\$(( \$(date +%s) + 3600 ))
  cat >"$primary_cooldown_file" <<OUT
ATTEMPTS=1
NEXT_ATTEMPT_EPOCH=\${future_epoch}
NEXT_ATTEMPT_AT=2099-01-01T00:00:00Z
LAST_REASON=provider-quota-limit
UPDATED_AT=2099-01-01T00:00:00Z
OUT
else
  cat >"$fallback_meta_file" <<'OUT'
LAST_FAILURE_REASON=
OUT
fi
EOF
chmod +x "$bin_dir/reconcile-issue-worker.sh"

FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
PATH="$shim_dir:$PATH" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_DIR="$capture_dir" \
bash "$bin_dir/start-resident-issue-loop.sh" 440 >/dev/null

controller_file="$state_root/resident-workers/issues/440/controller.env"

grep -q '^2$' "$capture_dir/start-count.txt"
grep -q '^START:440:1:openclaw$' "$capture_dir/events.log"
grep -q '^START:440:2:claude$' "$capture_dir/events.log"
grep -q '^RECONCILE:demo-issue-440:1$' "$capture_dir/events.log"
grep -q '^RECONCILE:demo-issue-440:2$' "$capture_dir/events.log"
grep -q '^CONTROLLER_REASON=idle-timeout$' "$controller_file"
grep -q '^CONTROLLER_STATE=stopped$' "$controller_file"
grep -q '^ACTIVE_PROVIDER_BACKEND=claude$' "$controller_file"
grep -q '^ACTIVE_PROVIDER_MODEL=fallback-sonnet$' "$controller_file"
grep -q '^LAST_PROVIDER_SWITCH_REASON=provider-failover$' "$controller_file"
grep -q '^LAST_PROVIDER_FROM_BACKEND=openclaw$' "$controller_file"
grep -q '^LAST_PROVIDER_TO_BACKEND=claude$' "$controller_file"
test "$(awk -F= '/^PROVIDER_SWITCH_COUNT=/{print $2}' "$controller_file")" -eq 1
test "$(awk -F= '/^PROVIDER_FAILOVER_COUNT=/{print $2}' "$controller_file")" -eq 1

echo "start resident issue loop provider pool failover test passed"
