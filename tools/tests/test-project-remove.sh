#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_REMOVE_BIN="${FLOW_ROOT}/tools/bin/project-remove.sh"

tmpdir="$(mktemp -d)"
managed_root_one="/tmp/agent-control-plane-remove-demo/test-$$-one"
managed_root_two="/tmp/agent-control-plane-purge-demo/test-$$-two"

cleanup() {
  rm -rf "${tmpdir}" "${managed_root_one}" "${managed_root_two}"
}
trap cleanup EXIT

write_profile() {
  local profile_root="${1:?profile root required}"
  local profile_id="${2:?profile id required}"
  local repo_root="${3:?repo root required}"
  local agent_root="${4:?agent root required}"
  local worktree_root="${5:?worktree root required}"
  local retained_root="${6:?retained root required}"
  local workspace_file="${7:?workspace file required}"
  local runs_root="${agent_root}/runs"
  local state_root="${agent_root}/state"
  local history_root="${agent_root}/history"

  mkdir -p "${profile_root}/${profile_id}" "${repo_root}" "${runs_root}" "${state_root}" "${history_root}" "${worktree_root}" "${retained_root}"
  printf 'notes\n' >"${profile_root}/${profile_id}/README.md"
  printf '{}\n' >"${workspace_file}"
  cat >"${profile_root}/${profile_id}/control-plane.yaml" <<EOF
schema_version: "1"
id: "${profile_id}"
repo:
  slug: "example/${profile_id}"
  root: "${repo_root}"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${agent_root}"
  worktree_root: "${worktree_root}"
  agent_repo_root: "${repo_root}"
  runs_root: "${runs_root}"
  state_root: "${state_root}"
  history_root: "${history_root}"
  retained_repo_root: "${retained_root}"
  vscode_workspace_file: "${workspace_file}"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 600
EOF
}

runtimectl_log="${tmpdir}/runtimectl.log"
runtimectl_stub="${tmpdir}/project-runtimectl.sh"
launchd_uninstall_log="${tmpdir}/launchd-uninstall.log"
launchd_uninstall_stub="${tmpdir}/uninstall-project-launchd.sh"
cat >"${runtimectl_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${runtimectl_log}"
printf 'ACTION=stop\nRUNTIME_STATUS=stopped\n'
EOF
chmod +x "${runtimectl_stub}"

cat >"${launchd_uninstall_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${launchd_uninstall_log}"
printf 'LAUNCHD_UNINSTALL_STATUS=ok\n'
EOF
chmod +x "${launchd_uninstall_stub}"

profile_registry_one="${tmpdir}/profiles-one"
repo_root_one="${tmpdir}/external-repo-one"
worktree_root_one="${tmpdir}/external-worktrees-one"
retained_root_one="${tmpdir}/external-retained-one"
workspace_file_one="${tmpdir}/external-one.code-workspace"
agent_root_one="${managed_root_one}/runtime/remove-demo"

write_profile "${profile_registry_one}" "remove-demo" "${repo_root_one}" "${agent_root_one}" "${worktree_root_one}" "${retained_root_one}" "${workspace_file_one}"

output_one="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_one}" \
  ACP_PROJECT_REMOVE_RUNTIMECTL_SCRIPT="${runtimectl_stub}" \
  ACP_PROJECT_REMOVE_LAUNCHD_UNINSTALL_SCRIPT="${launchd_uninstall_stub}" \
    bash "${PROJECT_REMOVE_BIN}" --profile-id remove-demo
)"

grep -q 'PROJECT_REMOVE_STATUS=ok' <<<"${output_one}"
grep -q 'PROFILE_ID=remove-demo' <<<"${output_one}"
grep -q 'PURGE_PATHS=0' <<<"${output_one}"
grep -q 'SKIP_STOP=0' <<<"${output_one}"
grep -q 'stop --profile-id remove-demo' "${runtimectl_log}"
grep -q -- '--profile-id remove-demo' "${launchd_uninstall_log}"
[[ ! -e "${profile_registry_one}/remove-demo" ]]
[[ ! -e "${agent_root_one}" ]]
[[ -d "${repo_root_one}" ]]
[[ -d "${worktree_root_one}" ]]
[[ -d "${retained_root_one}" ]]
[[ -f "${workspace_file_one}" ]]
grep -q "SKIPPED_PATHS=.*${repo_root_one}" <<<"${output_one}"
grep -q "SKIPPED_PATHS=.*${worktree_root_one}" <<<"${output_one}"
grep -q "SKIPPED_PATHS=.*${retained_root_one}" <<<"${output_one}"

profile_registry_two="${tmpdir}/profiles-two"
repo_root_two="${tmpdir}/external-repo-two"
worktree_root_two="${tmpdir}/external-worktrees-two"
retained_root_two="${tmpdir}/external-retained-two"
workspace_file_two="${tmpdir}/external-two.code-workspace"
agent_root_two="${managed_root_two}/runtime/purge-demo"

write_profile "${profile_registry_two}" "purge-demo" "${repo_root_two}" "${agent_root_two}" "${worktree_root_two}" "${retained_root_two}" "${workspace_file_two}"

output_two="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_two}" \
  ACP_PROJECT_REMOVE_RUNTIMECTL_SCRIPT="${runtimectl_stub}" \
  ACP_PROJECT_REMOVE_LAUNCHD_UNINSTALL_SCRIPT="${launchd_uninstall_stub}" \
    bash "${PROJECT_REMOVE_BIN}" --profile-id purge-demo --purge-paths --skip-stop
)"

grep -q 'PROJECT_REMOVE_STATUS=ok' <<<"${output_two}"
grep -q 'PROFILE_ID=purge-demo' <<<"${output_two}"
grep -q 'PURGE_PATHS=1' <<<"${output_two}"
grep -q 'SKIP_STOP=1' <<<"${output_two}"
[[ ! -e "${profile_registry_two}/purge-demo" ]]
[[ ! -e "${agent_root_two}" ]]
[[ ! -e "${repo_root_two}" ]]
[[ ! -e "${worktree_root_two}" ]]
[[ ! -e "${retained_root_two}" ]]
[[ ! -e "${workspace_file_two}" ]]
! grep -q 'purge-demo' "${runtimectl_log}"
grep -q -- '--profile-id purge-demo' "${launchd_uninstall_log}"
grep -q "REMOVED_PATHS=.*${repo_root_two}" <<<"${output_two}"
grep -q "REMOVED_PATHS=.*${worktree_root_two}" <<<"${output_two}"
grep -q "REMOVED_PATHS=.*${retained_root_two}" <<<"${output_two}"

if ACP_PROFILE_REGISTRY_ROOT="${profile_registry_two}" \
  ACP_PROJECT_REMOVE_RUNTIMECTL_SCRIPT="${runtimectl_stub}" \
  ACP_PROJECT_REMOVE_LAUNCHD_UNINSTALL_SCRIPT="${launchd_uninstall_stub}" \
  bash "${PROJECT_REMOVE_BIN}" --profile-id purge-demo >/dev/null 2>"${tmpdir}/missing-remove.err"; then
  echo "expected missing profile remove to fail" >&2
  exit 1
fi

grep -q 'profile not installed: purge-demo' "${tmpdir}/missing-remove.err"

echo "project remove test passed"
