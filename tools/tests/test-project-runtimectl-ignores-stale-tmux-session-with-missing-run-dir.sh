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
tmux_kill_log="${tmpdir}/tmux-kill.log"
fake_bin="${tmpdir}/bin"

mkdir -p "${profile_dir}" "${runs_root}/demo-pr-2" "${state_root}" "${fake_bin}"

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

cat >"${runs_root}/demo-pr-2/run.env" <<'EOF'
SESSION=demo-pr-2
TASK_KIND=pr
TASK_ID=2
EOF

printf 'demo-pr-2\ndemo-pr-3\n' >"${tmux_sessions_file}"

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
    cat "\${sessions_file}"
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

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q 'ACTIVE_TMUX_SESSION_COUNT=1' <<<"${status_output}"
grep -q 'ACTIVE_TMUX_SESSIONS=demo-pr-2' <<<"${status_output}"
grep -q 'STALE_TMUX_SESSION_COUNT=1' <<<"${status_output}"
grep -q 'STALE_TMUX_SESSIONS=demo-pr-3' <<<"${status_output}"

stop_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_TMUX_BIN="${fake_bin}/tmux" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" stop --profile-id demo
)"

grep -q 'STOPPED_TMUX_SESSION_COUNT=1' <<<"${stop_output}"
grep -q 'STOPPED_STALE_TMUX_SESSION_COUNT=1' <<<"${stop_output}"
grep -q '^demo-pr-2$' "${tmux_kill_log}"
grep -q '^demo-pr-3$' "${tmux_kill_log}"

echo "project runtimectl ignores stale tmux session with missing run dir test passed"
