#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
state_root="${tmpdir}/runtime/demo/state"
launch_agents_dir="${tmpdir}/home/Library/LaunchAgents"
fake_bin="${tmpdir}/bin"
launchctl_log="${tmpdir}/launchctl.log"
launchctl_state="${tmpdir}/launchctl-running"
label="ai.agent.project.demo"
plist_path="${launch_agents_dir}/${label}.plist"

mkdir -p "${profile_dir}" "${state_root}" "${launch_agents_dir}" "${fake_bin}"

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
  runs_root: "${tmpdir}/runtime/demo/runs"
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

printf '<plist></plist>\n' >"${plist_path}"

cat >"${fake_bin}/launchctl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${launchctl_log}"
cmd="\${1:-}"
case "\${cmd}" in
  print)
    if [[ -f "${launchctl_state}" ]]; then
      exit 0
    fi
    exit 1
    ;;
  bootstrap|kickstart)
    : >"${launchctl_state}"
    exit 0
    ;;
  bootout)
    rm -f "${launchctl_state}"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "${fake_bin}/launchctl"

: >"${launchctl_state}"

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR="${launch_agents_dir}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="${fake_bin}/launchctl" \
  bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q '^RUNTIME_STATUS=stopped$' <<<"${status_output}"
grep -q '^LAUNCHD_STATE=running$' <<<"${status_output}"
grep -q "^LAUNCHD_LABEL=${label}$" <<<"${status_output}"
grep -q "^LAUNCHD_PLIST=${plist_path}$" <<<"${status_output}"

start_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR="${launch_agents_dir}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="${fake_bin}/launchctl" \
  bash "${RUNTIMECTL_BIN}" start --profile-id demo
)"

grep -q '^ACTION=start$' <<<"${start_output}"
grep -q '^START_MODE=launchd$' <<<"${start_output}"
grep -q '^LAUNCHD_STATE=running$' <<<"${start_output}"
grep -q "bootout gui/.*/${label}" "${launchctl_log}"
grep -q "bootstrap gui/.* ${plist_path}" "${launchctl_log}"
grep -q "kickstart -k gui/.*/${label}" "${launchctl_log}"

stop_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR="${launch_agents_dir}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="${fake_bin}/launchctl" \
  bash "${RUNTIMECTL_BIN}" stop --profile-id demo
)"

grep -q '^ACTION=stop$' <<<"${stop_output}"
grep -q '^LAUNCHD_STOPPED=yes$' <<<"${stop_output}"
grep -q '^RUNTIME_STATUS=stopped$' <<<"${stop_output}"
grep -q '^LAUNCHD_STATE=stopped$' <<<"${stop_output}"

echo "project runtimectl launchd test passed"
