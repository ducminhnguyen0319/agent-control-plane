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
kick_log="${tmpdir}/kick.log"
fake_bin="${tmpdir}/bin"

mkdir -p "${profile_dir}" "${fake_bin}" "${runs_root}" "${state_root}"

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
  coding_worker: "codex"
EOF

sleep 60 >/dev/null 2>&1 &
supervisor_pid="$!"
sleep_pids+=("${supervisor_pid}")
printf '%s\n' "${supervisor_pid}" >"${state_root}/runtime-supervisor.pid"

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

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"
grep -q 'RUNTIME_STATUS=partial' <<<"${status_output}"

start_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" start --profile-id demo --delay-seconds 0
)"

grep -q 'ACTION=start' <<<"${start_output}"
grep -q 'START_MODE=kick-scheduler' <<<"${start_output}"
grep -q 'RUNTIME_STATUS=running' <<<"${start_output}"
grep -q 'kick profile=demo delay=0' "${kick_log}"

new_heartbeat_pid="$(tr -d '[:space:]' <"${state_root}/heartbeat-loop.lock/pid")"
if [[ -n "${new_heartbeat_pid}" ]]; then
  sleep_pids+=("${new_heartbeat_pid}")
fi

echo "project runtimectl start recovers supervisor-only runtime test passed"
