#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
sleep_pids=()
cleanup() {
  local pid=""
  for pid in "${sleep_pids[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
runs_root="${tmpdir}/runtime/demo/runs"
state_root="${tmpdir}/runtime/demo/state"
tmux_sessions_file="${tmpdir}/tmux-sessions.txt"
tmux_kill_log="${tmpdir}/tmux-kill.log"
kick_log="${tmpdir}/kick.log"
fake_bin="${tmpdir}/bin"
mkdir -p "${profile_dir}" "${runs_root}/demo-issue-1" "${runs_root}/demo-pr-2" "${state_root}/heartbeat-loop.lock" "${state_root}/pending-launches" "${state_root}/resident-workers/issues/1" "${fake_bin}"

cat >"${profile_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "${tmpdir}/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo"
  worktree_root: "${tmpdir}/worktrees"
  agent_repo_root: "${tmpdir}/repo"
  runs_root: "${runs_root}"
  state_root: "${state_root}"
  history_root: "${tmpdir}/runtime/demo/history"
  retained_repo_root: "${tmpdir}/repo"
  vscode_workspace_file: "${tmpdir}/demo.code-workspace"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

cat >"${runs_root}/demo-issue-1/run.env" <<'EOF'
SESSION=demo-issue-1
TASK_KIND=issue
TASK_ID=1
EOF

cat >"${runs_root}/demo-pr-2/run.env" <<'EOF'
SESSION=demo-pr-2
TASK_KIND=pr
TASK_ID=2
EOF

printf 'demo-issue-1\ndemo-pr-2\n' >"${tmux_sessions_file}"

cat >"${fake_bin}/tmux" <<EOF
#!/usr/bin/env bash
set -euo pipefail
sessions_file="${tmux_sessions_file}"
kill_log="${tmux_kill_log}"
cmd="\${1:-}"
case "\${cmd}" in
  has-session)
    shift
    [[ "\${1:-}" == "-t" ]] || exit 1
    session="\${2:-}"
    grep -Fxq "\${session}" "\${sessions_file}"
    ;;
  list-sessions)
    shift || true
    if [[ "\${1:-}" == "-F" ]]; then
      cat "\${sessions_file}"
    else
      cat "\${sessions_file}"
    fi
    ;;
  kill-session)
    shift
    [[ "\${1:-}" == "-t" ]] || exit 1
    session="\${2:-}"
    printf '%s\n' "\${session}" >>"\${kill_log}"
    grep -Fxv "\${session}" "\${sessions_file}" >"\${sessions_file}.next" || true
    mv "\${sessions_file}.next" "\${sessions_file}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${fake_bin}/tmux"

cat >"${fake_bin}/kick-scheduler.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'kick profile=%s delay=%s\n' "\${ACP_PROJECT_ID:-}" "\${1:-}" >>"${kick_log}"
mkdir -p "${state_root}/heartbeat-loop.lock"
sleep 60 >/dev/null 2>&1 &
echo \$! > "${state_root}/heartbeat-loop.lock/pid"
printf 'KICK_STATUS=scheduled\nPID=%s\n' "\$!"
EOF
chmod +x "${fake_bin}/kick-scheduler.sh"

sleep 60 &
heartbeat_pid="$!"
sleep_pids+=("${heartbeat_pid}")
printf '%s\n' "${heartbeat_pid}" >"${state_root}/heartbeat-loop.lock/pid"

sleep 60 &
shared_loop_pid="$!"
sleep_pids+=("${shared_loop_pid}")
printf '%s\n' "${shared_loop_pid}" >"${state_root}/shared-heartbeat-loop.pid"

sleep 60 &
controller_pid="$!"
sleep_pids+=("${controller_pid}")
cat >"${state_root}/resident-workers/issues/1/controller.env" <<EOF
ISSUE_ID=1
CONTROLLER_PID=${controller_pid}
EOF

sleep 60 &
pending_pid="$!"
sleep_pids+=("${pending_pid}")
printf '%s\n' "${pending_pid}" >"${state_root}/pending-launches/issue-1.pid"

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q 'RUNTIME_STATUS=running' <<<"${status_output}"
grep -q 'CONTROLLER_COUNT=1' <<<"${status_output}"
grep -q 'ACTIVE_TMUX_SESSION_COUNT=2' <<<"${status_output}"
grep -q 'STALE_TMUX_SESSION_COUNT=0' <<<"${status_output}"

stop_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" stop --profile-id demo --wait-seconds 1
)"

grep -q 'ACTION=stop' <<<"${stop_output}"
grep -q 'RUNTIME_STATUS=stopped' <<<"${stop_output}"
grep -q 'STOPPED_TMUX_SESSION_COUNT=2' <<<"${stop_output}"
grep -q 'STOPPED_STALE_TMUX_SESSION_COUNT=0' <<<"${stop_output}"
grep -q 'STOPPED_PID_COUNT=3' <<<"${stop_output}"

! kill -0 "${heartbeat_pid}" 2>/dev/null
! kill -0 "${shared_loop_pid}" 2>/dev/null
! kill -0 "${controller_pid}" 2>/dev/null
! kill -0 "${pending_pid}" 2>/dev/null
[[ ! -s "${tmux_sessions_file}" ]]

start_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" start --profile-id demo --delay-seconds 0
)"

grep -q 'ACTION=start' <<<"${start_output}"
grep -q 'START_MODE=kick-scheduler' <<<"${start_output}"
grep -q 'RUNTIME_STATUS=running' <<<"${start_output}"
grep -q 'kick profile=demo delay=0' "${kick_log}"
if grep -q 'FALLBACK_SUPERVISOR_PID=' <<<"${start_output}"; then
  echo "expected runtime started by kick-scheduler to avoid fallback supervisor" >&2
  exit 1
fi

new_heartbeat_pid="$(tr -d '[:space:]' <"${state_root}/heartbeat-loop.lock/pid")"
if [[ -n "${new_heartbeat_pid}" ]]; then
  sleep_pids+=("${new_heartbeat_pid}")
fi

start_again_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" start --profile-id demo --delay-seconds 0
)"

grep -q 'ACTION=start' <<<"${start_again_output}"
grep -q 'START_MODE=already-running' <<<"${start_again_output}"
grep -q 'NOOP=yes' <<<"${start_again_output}"
[[ "$(wc -l <"${kick_log}")" -eq 1 ]]

restart_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" restart --profile-id demo --delay-seconds 0 --wait-seconds 1
)"

grep -q 'ACTION=start' <<<"${restart_output}"
grep -q 'START_MODE=kick-scheduler' <<<"${restart_output}"
grep -q 'RUNTIME_STATUS=running' <<<"${restart_output}"
[[ "$(wc -l <"${kick_log}")" -eq 2 ]]
if grep -q 'FALLBACK_SUPERVISOR_PID=' <<<"${restart_output}"; then
  echo "expected restart to avoid fallback supervisor when kick-scheduler already restored runtime" >&2
  exit 1
fi

echo "project runtimectl test passed"
