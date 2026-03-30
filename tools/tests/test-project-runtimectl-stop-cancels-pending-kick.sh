#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"
KICK_SCRIPT="${FLOW_ROOT}/tools/bin/kick-scheduler.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
runs_root="${tmpdir}/runtime/demo/runs"
state_root="${tmpdir}/runtime/demo/state"
bootstrap_log="${tmpdir}/bootstrap.log"
bootstrap_script="${tmpdir}/bootstrap.sh"
mkdir -p "${profile_dir}" "${runs_root}" "${state_root}" "${tmpdir}/repo" "${tmpdir}/worktrees"

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

cat >"${bootstrap_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrap profile=%s\n' "\${ACP_PROJECT_ID:-}" >>"${bootstrap_log}"
mkdir -p "${state_root}/heartbeat-loop.lock"
sleep 60 >/dev/null 2>&1 &
printf '%s\n' "\$!" >"${state_root}/heartbeat-loop.lock/pid"
EOF
chmod +x "${bootstrap_script}"

kick_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_ID=demo \
  ACP_BOOTSTRAP_SCRIPT="${bootstrap_script}" \
    bash "${KICK_SCRIPT}" 2
)"

grep -q 'KICK_STATUS=scheduled' <<<"${kick_output}"
kick_pid_file="${state_root}/kick-scheduler/pid"
[[ -f "${kick_pid_file}" ]]

stop_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" stop --profile-id demo --wait-seconds 1
)"

grep -q 'ACTION=stop' <<<"${stop_output}"
grep -q 'RUNTIME_STATUS=stopped' <<<"${stop_output}"
[[ ! -f "${kick_pid_file}" ]]

sleep 3

if [[ -f "${bootstrap_log}" ]]; then
  echo "expected pending kick to be cancelled before bootstrap ran" >&2
  cat "${bootstrap_log}" >&2
  exit 1
fi

echo "project runtimectl cancels pending kick test passed"
