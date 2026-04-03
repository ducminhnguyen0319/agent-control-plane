#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/profile-activate.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  profile-activate.sh --profile-id <id> [--exports]

Print the selected profile context or shell export statements for quickly
switching operator commands to a specific installed profile.
EOF
}

profile_id=""
exports_only="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id="${2:-}"; shift 2 ;;
    --exports) exports_only="1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "${profile_id}" ]]; then
  usage >&2
  exit 1
fi

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
PROFILE_REGISTRY_ROOT="$(resolve_flow_profile_registry_root)"
CONFIG_YAML="$(flow_find_profile_dir_by_id "${FLOW_SKILL_DIR}" "${profile_id}")/control-plane.yaml"
PROFILE_NOTES="$(flow_resolve_profile_notes_file "${CONFIG_YAML}")"
AVAILABLE_PROFILES="$(flow_list_profile_ids "${FLOW_SKILL_DIR}" | paste -sd, -)"

if [[ ! -f "${CONFIG_YAML}" ]]; then
  echo "unknown profile id: ${profile_id}" >&2
  echo "AVAILABLE_PROFILES=${AVAILABLE_PROFILES}" >&2
  exit 1
fi

export ACP_PROJECT_ID="${profile_id}"
export AGENT_PROJECT_ID="${profile_id}"
flow_export_execution_env "${CONFIG_YAML}"

REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
CODING_WORKER="${ACP_CODING_WORKER:-codex}"
ACTIVE_PROVIDER_POOL_NAME="${ACP_ACTIVE_PROVIDER_POOL_NAME:-${F_LOSNING_ACTIVE_PROVIDER_POOL_NAME:-}}"

if [[ "${exports_only}" == "1" ]]; then
  printf 'export ACP_PROJECT_ID=%q
' "${profile_id}"
  printf 'export AGENT_PROJECT_ID=%q
' "${profile_id}"
  printf 'export ACP_PROFILE_REGISTRY_ROOT=%q
' "${PROFILE_REGISTRY_ROOT}"
  printf 'export ACP_CONFIG=%q
' "${CONFIG_YAML}"
  printf 'export ACP_PROFILE_NOTES=%q
' "${PROFILE_NOTES}"
  printf 'export ACP_PROFILE_REPO_ROOT=%q
' "${REPO_ROOT}"
  printf 'export ACP_PROFILE_AGENT_ROOT=%q
' "${AGENT_ROOT}"
  exit 0
fi

printf 'PROFILE_ID=%s
' "${profile_id}"
printf 'PROFILE_REGISTRY_ROOT=%s
' "${PROFILE_REGISTRY_ROOT}"
printf 'CONFIG_YAML=%s
' "${CONFIG_YAML}"
printf 'PROFILE_NOTES=%s
' "${PROFILE_NOTES}"
printf 'AVAILABLE_PROFILES=%s
' "${AVAILABLE_PROFILES}"
printf 'REPO_SLUG=%s
' "${REPO_SLUG}"
printf 'REPO_ROOT=%s
' "${REPO_ROOT}"
printf 'AGENT_ROOT=%s
' "${AGENT_ROOT}"
printf 'AGENT_REPO_ROOT=%s
' "${AGENT_REPO_ROOT}"
printf 'WORKTREE_ROOT=%s
' "${WORKTREE_ROOT}"
printf 'RUNS_ROOT=%s
' "${RUNS_ROOT}"
printf 'STATE_ROOT=%s
' "${STATE_ROOT}"
printf 'CODING_WORKER=%s
' "${CODING_WORKER}"
printf 'ACTIVE_PROVIDER_POOL_NAME=%s
' "${ACTIVE_PROVIDER_POOL_NAME}"
printf 'NEXT_STEP=eval "$(%s --profile-id %s --exports)"
' "${SCRIPT_PATH}" "${profile_id}"
