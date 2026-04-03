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
tmux_sessions_file="${tmpdir}/tmux-sessions.txt"
fake_bin="${tmpdir}/bin"

mkdir -p "${profile_dir}" "${runs_root}/demo-issue-1" "${state_root}/resident-workers/issues/1" "${fake_bin}"

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

cat >"${runs_root}/demo-issue-1/run.env" <<'EOF'
SESSION=demo-issue-1
TASK_KIND=issue
TASK_ID=1
EOF

printf 'demo-issue-1\n' >"${tmux_sessions_file}"

cat >"${fake_bin}/tmux" <<EOF
#!/usr/bin/env bash
set -euo pipefail
sessions_file="${tmux_sessions_file}"
cmd="\${1:-}"
case "\${cmd}" in
  has-session)
    shift
    [[ "\${1:-}" == "-t" ]] || exit 1
    session="\${2:-}"
    grep -Fxq "\${session}" "\${sessions_file}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${fake_bin}/tmux"

sleep 60 >/dev/null 2>&1 &
controller_pid="$!"
cat >"${state_root}/resident-workers/issues/1/controller.env" <<EOF
ISSUE_ID=1
CONTROLLER_PID=${controller_pid}
EOF

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

kill "${controller_pid}" >/dev/null 2>&1 || true
wait "${controller_pid}" >/dev/null 2>&1 || true

grep -q 'RUNTIME_STATUS=running' <<<"${status_output}"
grep -q 'HEARTBEAT_PID=$' <<<"${status_output}"
grep -q 'ACTIVE_TMUX_SESSION_COUNT=1' <<<"${status_output}"

echo "project runtimectl active worker without heartbeat reports running"
