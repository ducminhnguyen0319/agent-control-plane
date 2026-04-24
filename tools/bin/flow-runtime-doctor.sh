#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
SHARED_AGENT_HOME="$(resolve_shared_agent_home "${FLOW_SKILL_DIR}")"
PROFILE_REGISTRY_ROOT="$(resolve_flow_profile_registry_root)"
CONTROL_PLANE_NAME="$(flow_canonical_skill_name)"
COMPAT_SKILL_ALIAS="$(flow_compat_skill_alias)"
SOURCE_CANONICAL_SKILL_DIR="$(resolve_source_canonical_skill_dir "${SHARED_AGENT_HOME}")"
SOURCE_COMPAT_SKILL_DIR="$(resolve_source_compat_skill_dir "${SHARED_AGENT_HOME}")"
RUNTIME_HOME="$(resolve_runtime_home)"
RUNTIME_CANONICAL_SKILL_DIR="$(resolve_runtime_canonical_skill_dir)"
RUNTIME_COMPAT_SKILL_DIR="$(resolve_runtime_compat_skill_dir)"
CATALOG_FILE="${FLOW_SKILL_DIR}/assets/workflow-catalog.json"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
SYNC_SCRIPT="${FLOW_SKILL_DIR}/tools/bin/sync-shared-agent-home.sh"
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
AVAILABLE_PROFILES="$(flow_list_profile_ids "${FLOW_SKILL_DIR}" | paste -sd, -)"
INSTALLED_PROFILES="$(flow_list_installed_profile_ids | paste -sd, -)"
PROFILE_SELECTION_MODE="$(flow_profile_selection_mode "${FLOW_SKILL_DIR}")"
PROFILE_SELECTION_HINT="$(flow_profile_selection_hint "${FLOW_SKILL_DIR}")"
PROFILE_NOTES="$(flow_resolve_profile_notes_file "${CONFIG_YAML}")"

exists_flag() {
  local candidate="${1:-}"
  if [[ -e "${candidate}" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

source_canonical_exists="$(exists_flag "${SOURCE_CANONICAL_SKILL_DIR}")"
source_compat_exists="$(exists_flag "${SOURCE_COMPAT_SKILL_DIR}")"
runtime_canonical_exists="$(exists_flag "${RUNTIME_CANONICAL_SKILL_DIR}")"
runtime_compat_exists="$(exists_flag "${RUNTIME_COMPAT_SKILL_DIR}")"
catalog_exists="$(exists_flag "${CATALOG_FILE}")"
profile_exists="$(exists_flag "${CONFIG_YAML}")"
active_checkout_is_canonical="no"
source_ready="${source_canonical_exists}"

if [[ "$(basename "${FLOW_SKILL_DIR}")" == "${CONTROL_PLANE_NAME}" ]]; then
  active_checkout_is_canonical="yes"
  source_ready="yes"
fi

status="ok"
if [[ "${source_ready}" != "yes" || "${runtime_canonical_exists}" != "yes" || "${profile_exists}" != "yes" ]]; then
  status="needs-sync"
fi

printf 'CONTROL_PLANE_NAME=%s\n' "${CONTROL_PLANE_NAME}"
printf 'COMPAT_SKILL_ALIAS=%s\n' "${COMPAT_SKILL_ALIAS}"
printf 'FLOW_SKILL_DIR=%s\n' "${FLOW_SKILL_DIR}"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "${PROFILE_REGISTRY_ROOT}"
printf 'CONFIG_YAML=%s\n' "${CONFIG_YAML}"
printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
printf 'PROFILE_SELECTION_MODE=%s\n' "${PROFILE_SELECTION_MODE}"
if [[ -n "${PROFILE_SELECTION_HINT}" ]]; then
  printf 'PROFILE_SELECTION_HINT=%s\n' "${PROFILE_SELECTION_HINT}"
fi
printf 'PROFILE_NOTES=%s\n' "${PROFILE_NOTES}"
if [[ -f "${PROFILE_NOTES}" ]]; then
  printf 'PROFILE_NOTES_EXISTS=yes\n'
else
  printf 'PROFILE_NOTES_EXISTS=no\n'
fi
printf 'PROFILE_EXISTS=%s\n' "${profile_exists}"
printf 'AVAILABLE_PROFILES=%s\n' "${AVAILABLE_PROFILES}"
printf 'INSTALLED_PROFILES=%s\n' "${INSTALLED_PROFILES}"
printf 'SHARED_AGENT_HOME=%s\n' "${SHARED_AGENT_HOME}"
printf 'SOURCE_CANONICAL_SKILL_DIR=%s\n' "${SOURCE_CANONICAL_SKILL_DIR}"
printf 'SOURCE_CANONICAL_EXISTS=%s\n' "${source_canonical_exists}"
printf 'ACTIVE_CHECKOUT_IS_CANONICAL=%s\n' "${active_checkout_is_canonical}"
printf 'SOURCE_READY=%s\n' "${source_ready}"
printf 'SOURCE_COMPAT_SKILL_DIR=%s\n' "${SOURCE_COMPAT_SKILL_DIR}"
printf 'SOURCE_COMPAT_EXISTS=%s\n' "${source_compat_exists}"
printf 'RUNTIME_HOME=%s\n' "${RUNTIME_HOME}"
printf 'RUNTIME_CANONICAL_SKILL_DIR=%s\n' "${RUNTIME_CANONICAL_SKILL_DIR}"
printf 'RUNTIME_CANONICAL_EXISTS=%s\n' "${runtime_canonical_exists}"
printf 'RUNTIME_COMPAT_SKILL_DIR=%s\n' "${RUNTIME_COMPAT_SKILL_DIR}"
printf 'RUNTIME_COMPAT_EXISTS=%s\n' "${runtime_compat_exists}"
printf 'WORKFLOW_CATALOG=%s\n' "${CATALOG_FILE}"
printf 'WORKFLOW_CATALOG_EXISTS=%s\n' "${catalog_exists}"
printf 'DOCTOR_STATUS=%s\n' "${status}"

if [[ -n "${PROFILE_SELECTION_HINT}" ]]; then
  printf 'PROFILE_SELECTION_NEXT_STEP=ACP_PROJECT_ID=<id> bash %s/tools/bin/render-flow-config.sh\n' "${FLOW_SKILL_DIR}"
fi

if [[ "${status}" != "ok" ]]; then
  printf '\n=== ACTION REQUIRED ===\n'
  printf 'Status: %s\n' "${status}"
  printf 'Next step: Run sync to fix issues:\n'
  printf '  bash %q %q %q\n' "${SYNC_SCRIPT}" "${SHARED_AGENT_HOME}" "${RUNTIME_HOME}"
  printf '\nOr run: bash %s/tools/bin/setup.sh --resume\n' "${FLOW_SKILL_DIR}"
fi
