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
mkdir -p "${profile_dir}" "${runs_root}" "${state_root}"

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

sleep 60 >/dev/null 2>&1 &
heartbeat_pid="$!"
printf '%s\n' "${heartbeat_pid}" >"${state_root}/heartbeat-loop.lock.pid.tmp"
mkdir -p "${state_root}/heartbeat-loop.lock"
mv "${state_root}/heartbeat-loop.lock.pid.tmp" "${state_root}/heartbeat-loop.lock/pid"

cat >"${state_root}/shared-heartbeat-loop.env" <<'EOF'
STATE=idle
STATUS=0
STARTED_AT=2026-04-03T19:40:00Z
UPDATED_AT=2026-04-03T19:41:00Z
EOF

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q '^SHARED_LOOP_PID=$' <<<"${status_output}"
grep -q '^SHARED_LOOP_STATE=idle$' <<<"${status_output}"
grep -q '^SHARED_LOOP_LAST_STATUS=0$' <<<"${status_output}"
grep -q '^SHARED_LOOP_STARTED_AT=2026-04-03T19:40:00Z$' <<<"${status_output}"
grep -q '^SHARED_LOOP_UPDATED_AT=2026-04-03T19:41:00Z$' <<<"${status_output}"

kill "${heartbeat_pid}" >/dev/null 2>&1 || true
wait "${heartbeat_pid}" >/dev/null 2>&1 || true

echo "project runtimectl shared loop state status test passed"
