#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  project-remove.sh --profile-id <id> [options]

Remove one installed profile from agent-control-plane. This stops the profile's
runtime first, then deletes the installed profile directory and ACP-managed
runtime roots. Repo/worktree/retained paths are only deleted when they look
like ACP-managed temp paths or when --purge-paths is supplied.

Options:
  --profile-id <id>      Profile id to remove
  --purge-paths          Also delete repo/worktree/retained/workspace paths
  --skip-stop            Skip project-runtimectl stop before deletion
  --help                 Show this help
EOF
}

profile_id_override=""
purge_paths="0"
skip_stop="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id_override="${2:-}"; shift 2 ;;
    --purge-paths) purge_paths="1"; shift ;;
    --skip-stop) skip_stop="1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "${profile_id_override}" ]]; then
  usage >&2
  exit 64
fi

export ACP_PROJECT_ID="${profile_id_override}"
export AGENT_PROJECT_ID="${profile_id_override}"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
if [[ ! -f "${CONFIG_YAML}" ]]; then
  printf 'profile not installed: %s\n' "${profile_id_override}" >&2
  exit 66
fi
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
PROFILE_REGISTRY_ROOT="$(resolve_flow_profile_registry_root)"
PROFILE_DIR="$(dirname "${CONFIG_YAML}")"
REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
RETAINED_REPO_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
VSCODE_WORKSPACE_FILE="$(flow_resolve_vscode_workspace_file "${CONFIG_YAML}")"
PROJECT_RUNTIMECTL="${ACP_PROJECT_REMOVE_RUNTIMECTL_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/project-runtimectl.sh}"
PROJECT_LAUNCHD_UNINSTALL="${ACP_PROJECT_REMOVE_LAUNCHD_UNINSTALL_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/uninstall-project-launchd.sh}"

managed_tmp_prefix="/tmp/agent-control-plane-${PROFILE_ID}"
managed_runtime_prefix="${HOME}/.agent-runtime"

path_exists() {
  local path="${1:-}"
  [[ -n "${path}" && -e "${path}" ]]
}

path_is_managed() {
  local path="${1:-}"
  [[ -n "${path}" ]] || return 1
  case "${path}" in
    "${managed_tmp_prefix}"|"${managed_tmp_prefix}/"*|\
    "${managed_runtime_prefix}"|"${managed_runtime_prefix}/"*)
      return 0
      ;;
  esac
  return 1
}

remove_path_if_present() {
  local path="${1:-}"
  [[ -n "${path}" ]] || return 0
  if [[ -L "${path}" || -f "${path}" ]]; then
    rm -f "${path}"
  elif [[ -d "${path}" ]]; then
    rm -rf "${path}"
  fi
}

removed_paths=""
skipped_paths=""

record_removed() {
  local path="${1:-}"
  [[ -n "${path}" ]] || return 0
  removed_paths="${removed_paths}${removed_paths:+$'\n'}${path}"
}

record_skipped() {
  local path="${1:-}"
  [[ -n "${path}" ]] || return 0
  skipped_paths="${skipped_paths}${skipped_paths:+$'\n'}${path}"
}

delete_owned_path() {
  local path="${1:-}"
  path_exists "${path}" || return 0
  remove_path_if_present "${path}"
  record_removed "${path}"
}

delete_optional_path() {
  local path="${1:-}"
  path_exists "${path}" || return 0
  if [[ "${purge_paths}" == "1" ]] || path_is_managed "${path}"; then
    remove_path_if_present "${path}"
    record_removed "${path}"
  else
    record_skipped "${path}"
  fi
}

if [[ "${skip_stop}" != "1" ]]; then
  bash "${PROJECT_RUNTIMECTL}" stop --profile-id "${PROFILE_ID}" >/dev/null
fi

if [[ -x "${PROJECT_LAUNCHD_UNINSTALL}" ]]; then
  bash "${PROJECT_LAUNCHD_UNINSTALL}" --profile-id "${PROFILE_ID}" >/dev/null 2>&1 || true
fi

delete_owned_path "${RUNS_ROOT}"
delete_owned_path "${STATE_ROOT}"
delete_owned_path "${HISTORY_ROOT}"
delete_owned_path "${AGENT_ROOT}"
delete_optional_path "${WORKTREE_ROOT}"
delete_optional_path "${RETAINED_REPO_ROOT}"
delete_optional_path "${VSCODE_WORKSPACE_FILE}"
delete_optional_path "${REPO_ROOT}"
delete_owned_path "${PROFILE_DIR}"

printf 'PROJECT_REMOVE_STATUS=ok\n'
printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "${PROFILE_REGISTRY_ROOT}"
printf 'PURGE_PATHS=%s\n' "${purge_paths}"
printf 'SKIP_STOP=%s\n' "${skip_stop}"
printf 'REMOVED_PATHS=%s\n' "$(printf '%s\n' "${removed_paths}" | awk 'NF {printf "%s%s", sep, $0; sep=","} END {print ""}')"
printf 'SKIPPED_PATHS=%s\n' "$(printf '%s\n' "${skipped_paths}" | awk 'NF {printf "%s%s", sep, $0; sep=","} END {print ""}')"
