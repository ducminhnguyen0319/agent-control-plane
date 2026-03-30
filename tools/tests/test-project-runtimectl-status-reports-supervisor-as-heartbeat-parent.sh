#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
supervisor_pid=""
heartbeat_pid=""
cleanup() {
  if [[ -n "${heartbeat_pid}" ]]; then
    kill "${heartbeat_pid}" >/dev/null 2>&1 || true
    wait "${heartbeat_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${supervisor_pid}" ]]; then
    kill "${supervisor_pid}" >/dev/null 2>&1 || true
    wait "${supervisor_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
runs_root="${tmpdir}/runtime/demo/runs"
state_root="${tmpdir}/runtime/demo/state"
heartbeat_lock_dir="${state_root}/heartbeat-loop.lock"
mkdir -p "${profile_dir}" "${runs_root}" "${heartbeat_lock_dir}"

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

supervisor_script="${tmpdir}/project-runtime-supervisor.sh"
child_pid_file="${tmpdir}/heartbeat-child.pid"
cat >"${supervisor_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
sleep 60 >/dev/null 2>&1 &
child_pid=\$!
printf '%s\n' "\${child_pid}" >"${child_pid_file}"
wait "\${child_pid}"
EOF
chmod +x "${supervisor_script}"

bash "${supervisor_script}" >/dev/null 2>&1 &
supervisor_pid="$!"

for _ in $(seq 1 50); do
  if [[ -s "${child_pid_file}" ]]; then
    break
  fi
  sleep 0.1
done

heartbeat_pid="$(tr -d '[:space:]' <"${child_pid_file}")"
if [[ -z "${heartbeat_pid}" ]]; then
  echo "failed to capture heartbeat child pid" >&2
  exit 1
fi

printf '%s\n' "${heartbeat_pid}" >"${heartbeat_lock_dir}/pid"
printf '%s\n' "${supervisor_pid}" >"${state_root}/runtime-supervisor.pid"

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q "HEARTBEAT_PID=${heartbeat_pid}" <<<"${status_output}"
grep -q "HEARTBEAT_PARENT_PID=${supervisor_pid}" <<<"${status_output}"
grep -q "SUPERVISOR_PID=${supervisor_pid}" <<<"${status_output}"

echo "project runtimectl status reports supervisor as heartbeat parent test passed"
