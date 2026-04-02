#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
runs_root="${tmpdir}/runtime/demo/runs"
state_root="${tmpdir}/runtime/demo/state"
fake_bin="${tmpdir}/bin"
kick_log="${tmpdir}/kick.log"
bootstrap_log="${tmpdir}/bootstrap.log"
mkdir -p "${profile_dir}" "${fake_bin}" "${tmpdir}/repo" "${tmpdir}/worktrees" "${tmpdir}/runtime/demo"

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

cat >"${fake_bin}/kick-scheduler.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'kick profile=%s delay=%s\n' "\${ACP_PROJECT_ID:-}" "\${1:-}" >>"${kick_log}"
printf 'KICK_STATUS=scheduled\nPID=99999\n'
EOF
chmod +x "${fake_bin}/kick-scheduler.sh"

cat >"${fake_bin}/bootstrap.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrap profile=%s\n' "\${ACP_PROJECT_ID:-}" >>"${bootstrap_log}"
mkdir -p "${state_root}/heartbeat-loop.lock"
sleep 60 >/dev/null 2>&1 &
child_pid="\$!"
printf '%s\n' "\$child_pid" >"${state_root}/heartbeat-loop.lock/pid"
wait "\$child_pid"
EOF
chmod +x "${fake_bin}/bootstrap.sh"

start_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT="${fake_bin}/bootstrap.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
  ACP_PROJECT_RUNTIME_START_WAIT_SECONDS=1 \
    bash "${RUNTIMECTL_BIN}" start --profile-id demo --delay-seconds 0
)"

grep -q 'ACTION=start' <<<"${start_output}"
grep -q 'PROFILE_ID=demo' <<<"${start_output}"
grep -q 'START_MODE=kick-scheduler-fallback-supervisor' <<<"${start_output}"
grep -q 'KICK_STATUS=scheduled' <<<"${start_output}"
grep -q 'FALLBACK_SUPERVISOR_PID=' <<<"${start_output}"
grep -q '^FALLBACK_SUPERVISOR_LOG=' <<<"${start_output}"
grep -q 'kick profile=demo delay=0' "${kick_log}"

for _ in 1 2 3 4 5; do
  if [[ -f "${bootstrap_log}" ]] && grep -q 'bootstrap profile=demo' "${bootstrap_log}"; then
    break
  fi
  sleep 1
done

grep -q 'bootstrap profile=demo' "${bootstrap_log}"

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
  ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT="${fake_bin}/bootstrap.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q 'RUNTIME_STATUS=running' <<<"${status_output}"
grep -q 'SUPERVISOR_PID=' <<<"${status_output}"

ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-scheduler.sh" \
ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT="${fake_bin}/bootstrap.sh" \
ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
  bash "${RUNTIMECTL_BIN}" stop --profile-id demo --wait-seconds 1 >/dev/null

echo "project runtimectl bootstrap fallback test passed"
