#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

HOME_DIR="${HOME:-$(eval printf '%s' ~)}"
CANONICAL_FLOW_SKILL_NAME="${AGENT_CONTROL_PLANE_SKILL_NAME:-agent-control-plane}"
COMPAT_FLOW_SKILL_ALIAS="${AGENT_CONTROL_PLANE_COMPAT_ALIAS:-}"
DEPRECATED_FLOW_SKILL_ALIASES_RAW="${AGENT_CONTROL_PLANE_DEPRECATED_SKILL_ALIASES:-}"
FLOW_SKILL_SOURCE="${AGENT_FLOW_SOURCE_ROOT:-$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")}"
SOURCE_HOME="${1:-$(resolve_shared_agent_home "${FLOW_SKILL_SOURCE}")}"
AGENT_PLATFORM_HOME="${AGENT_PLATFORM_HOME:-${HOME_DIR}/.agent-runtime}"
TARGET_HOME="${2:-${AGENT_PLATFORM_HOME}/runtime-home}"
FLOW_SKILL_TARGET="${TARGET_HOME}/skills/openclaw/${CANONICAL_FLOW_SKILL_NAME}"
SOURCE_FLOW_CANONICAL_ALIAS="${SOURCE_HOME}/skills/openclaw/${CANONICAL_FLOW_SKILL_NAME}"
TARGET_FLOW_COMPAT_ALIAS=""
SOURCE_FLOW_COMPAT_ALIAS=""

if [[ -n "${COMPAT_FLOW_SKILL_ALIAS}" ]]; then
  TARGET_FLOW_COMPAT_ALIAS="${TARGET_HOME}/skills/openclaw/${COMPAT_FLOW_SKILL_ALIAS}"
  SOURCE_FLOW_COMPAT_ALIAS="${SOURCE_HOME}/skills/openclaw/${COMPAT_FLOW_SKILL_ALIAS}"
fi

if [[ ! -d "${FLOW_SKILL_SOURCE}" ]]; then
  FLOW_SKILL_SOURCE="${SOURCE_HOME}/skills/openclaw/${CANONICAL_FLOW_SKILL_NAME}"
fi

if [[ ! -d "${FLOW_SKILL_SOURCE}" && -n "${COMPAT_FLOW_SKILL_ALIAS}" ]]; then
  FLOW_SKILL_SOURCE="${SOURCE_HOME}/skills/openclaw/${COMPAT_FLOW_SKILL_ALIAS}"
fi

FLOW_SKILL_SOURCE="$(cd "${FLOW_SKILL_SOURCE}" && pwd -P)"
SOURCE_HOME="$(cd "${SOURCE_HOME}" && pwd -P)"

remove_tree_force() {
  local target="${1:-}"
  [[ -n "${target}" ]] || return 0
  [[ -e "${target}" || -L "${target}" ]] || return 0
  chmod -R u+w "${target}" 2>/dev/null || true
  rm -rf "${target}" 2>/dev/null || true
}

sync_tree_copy_mode() {
  local source_dir="${1:?source dir required}"
  local target_dir="${2:?target dir required}"
  [[ -d "${source_dir}" ]] || return 0
  remove_tree_force "${target_dir}"
  mkdir -p "${target_dir}"
  (
    cd "${source_dir}"
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -R {} "${target_dir}/" \;
  )
}

sync_tree_into_target() {
  local source_dir="${1:?source dir required}"
  local target_dir="${2:?target dir required}"
  [[ -n "${target_dir}" ]] || return 0
  if command -v rsync >/dev/null 2>&1; then
    sync_tree_rsync "${source_dir}" "${target_dir}"
  else
    sync_tree_copy_mode "${source_dir}" "${target_dir}"
  fi
}

sync_skill_copies() {
  if ! flow_is_skill_root "${SOURCE_HOME}"; then
    sync_tree_into_target "${FLOW_SKILL_SOURCE}" "${SOURCE_FLOW_CANONICAL_ALIAS}"
    if [[ -n "${SOURCE_FLOW_COMPAT_ALIAS}" ]]; then
      sync_tree_into_target "${FLOW_SKILL_SOURCE}" "${SOURCE_FLOW_COMPAT_ALIAS}"
    fi
  fi

  sync_tree_into_target "${FLOW_SKILL_SOURCE}" "${FLOW_SKILL_TARGET}"

  if [[ -n "${TARGET_FLOW_COMPAT_ALIAS}" ]]; then
    sync_tree_into_target "${FLOW_SKILL_SOURCE}" "${TARGET_FLOW_COMPAT_ALIAS}"
  fi
}

refresh_legacy_profile_templates() {
  local profiles_root=""
  local current_issue_template=""
  local legacy_issue_template=""
  local profile_dir=""
  local profile_issue_template=""

  profiles_root="$(resolve_flow_profile_registry_root)"
  current_issue_template="${FLOW_SKILL_SOURCE}/tools/templates/issue-prompt-template.md"
  legacy_issue_template="${FLOW_SKILL_SOURCE}/tools/templates/legacy/issue-prompt-template-pre-slim.md"

  [[ -d "${profiles_root}" ]] || return 0
  [[ -f "${current_issue_template}" ]] || return 0
  [[ -f "${legacy_issue_template}" ]] || return 0

  while IFS= read -r profile_dir; do
    [[ -n "${profile_dir}" ]] || continue
    profile_issue_template="${profile_dir}/templates/issue-prompt-template.md"
    [[ -f "${profile_issue_template}" ]] || continue
    if cmp -s "${profile_issue_template}" "${legacy_issue_template}"; then
      cp "${current_issue_template}" "${profile_issue_template}"
    fi
  done < <(find "${profiles_root}" -mindepth 2 -maxdepth 2 -type f -name 'control-plane.yaml' -exec dirname {} \; 2>/dev/null | sort)
}

remove_repo_local_profile_dirs() {
  local candidate=""

  for candidate in \
    "${SOURCE_FLOW_CANONICAL_ALIAS}" \
    "${FLOW_SKILL_TARGET}" \
    "${SOURCE_FLOW_COMPAT_ALIAS}" \
    "${TARGET_FLOW_COMPAT_ALIAS}"; do
    [[ -n "${candidate}" ]] || continue
    [[ -d "${candidate}" ]] || continue
    rm -rf "${candidate}/profiles"
  done
}

list_deprecated_skill_aliases() {
  local alias_name=""
  local raw_aliases="${DEPRECATED_FLOW_SKILL_ALIASES_RAW//,/ }"

  for alias_name in ${raw_aliases}; do
    [[ -n "${alias_name}" ]] || continue
    [[ "${alias_name}" == "${CANONICAL_FLOW_SKILL_NAME}" ]] && continue
    if [[ -n "${COMPAT_FLOW_SKILL_ALIAS}" && "${alias_name}" == "${COMPAT_FLOW_SKILL_ALIAS}" ]]; then
      continue
    fi
    printf '%s\n' "${alias_name}"
  done
}

is_flow_skill_copy_dir() {
  local dir="${1:-}"
  [[ -n "${dir}" ]] || return 1
  [[ -f "${dir}/assets/workflow-catalog.json" ]] || return 1

  if [[ ! -f "${dir}/SKILL.md" ]]; then
    return 0
  fi

  [[ -f "${dir}/tools/bin/sync-shared-agent-home.sh" ]] || return 1
  [[ -f "${dir}/tools/bin/flow-runtime-doctor.sh" ]] || return 1
  return 0
}

cleanup_stale_flow_skill_dirs() {
  local skills_root=""
  local dir=""
  local dir_name=""

  for skills_root in "${SOURCE_HOME}/skills/openclaw" "${TARGET_HOME}/skills/openclaw"; do
    [[ -d "${skills_root}" ]] || continue
    for dir in "${skills_root}"/*; do
      [[ -d "${dir}" ]] || continue
      dir_name="$(basename "${dir}")"
      [[ "${dir_name}" == "${CANONICAL_FLOW_SKILL_NAME}" ]] && continue
      if [[ -n "${COMPAT_FLOW_SKILL_ALIAS}" && "${dir_name}" == "${COMPAT_FLOW_SKILL_ALIAS}" ]]; then
        continue
      fi
      is_flow_skill_copy_dir "${dir}" || continue
      rm -rf "${dir}"
    done
  done
}

reset_deprecated_skill_targets() {
  local alias_name=""

  while IFS= read -r alias_name; do
    [[ -n "${alias_name}" ]] || continue
    rm -rf "${SOURCE_HOME}/skills/openclaw/${alias_name}" "${TARGET_HOME}/skills/openclaw/${alias_name}"
  done < <(list_deprecated_skill_aliases)
}

cleanup_legacy_flow_publication_dirs() {
  local root=""

  for root in "${SOURCE_HOME}" "${TARGET_HOME}"; do
    [[ -d "${root}" ]] || continue
    rm -rf "${root}/flows/project-adapters" "${root}/flows/profiles"
  done
}

normalize_script_permissions() {
  local root

  for root in \
    "${TARGET_HOME}/tools/bin" \
    "${TARGET_HOME}/tools/vendor/codex-quota-manager/scripts" \
    "${FLOW_SKILL_TARGET}/bin" \
    "${FLOW_SKILL_TARGET}/hooks" \
    "${FLOW_SKILL_TARGET}/tools/bin" \
    "${FLOW_SKILL_TARGET}/tools/tests" \
    "${FLOW_SKILL_TARGET}/tools/vendor/codex-quota-manager/scripts" \
    "${TARGET_HOME}/skills/openclaw/codex-quota-manager/scripts"; do
    [[ -d "${root}" ]] || continue
    find "${root}" -type f -exec chmod +x {} + 2>/dev/null || true
  done
}

sync_tree_rsync() {
  local source_dir="${1:?source dir required}"
  local target_dir="${2:?target dir required}"
  [[ -d "${source_dir}" ]] || return 0
  mkdir -p "${target_dir}"
  if rsync -a --delete --exclude='.git/' "${source_dir}/" "${target_dir}/"; then
    return 0
  fi
  sync_tree_copy_mode "${source_dir}" "${target_dir}"
}

reset_runtime_skill_targets() {
  remove_tree_force "${FLOW_SKILL_TARGET}"
  if [[ -n "${TARGET_FLOW_COMPAT_ALIAS}" ]]; then
    remove_tree_force "${TARGET_FLOW_COMPAT_ALIAS}"
  fi
}

reset_source_skill_targets() {
  if flow_is_skill_root "${SOURCE_HOME}"; then
    return 0
  fi
  if [[ "${FLOW_SKILL_SOURCE}" != "${SOURCE_FLOW_CANONICAL_ALIAS}" ]]; then
    remove_tree_force "${SOURCE_FLOW_CANONICAL_ALIAS}"
  fi
  if [[ -n "${SOURCE_FLOW_COMPAT_ALIAS}" && "${FLOW_SKILL_SOURCE}" != "${SOURCE_FLOW_COMPAT_ALIAS}" ]]; then
    remove_tree_force "${SOURCE_FLOW_COMPAT_ALIAS}"
  fi
}

mkdir -p "${TARGET_HOME}/tools" "${TARGET_HOME}/skills/openclaw"
mkdir -p "${SOURCE_HOME}/skills/openclaw"
reset_source_skill_targets
reset_runtime_skill_targets
reset_deprecated_skill_targets
cleanup_stale_flow_skill_dirs
cleanup_legacy_flow_publication_dirs

if command -v rsync >/dev/null 2>&1; then
  sync_tree_rsync "${SOURCE_HOME}/tools" "${TARGET_HOME}/tools"
  sync_tree_rsync "${SOURCE_HOME}/skills/openclaw/codex-quota-manager" "${TARGET_HOME}/skills/openclaw/codex-quota-manager"
else
  mkdir -p "${TARGET_HOME}/tools" "${TARGET_HOME}/skills/openclaw"
  sync_tree_copy_mode "${SOURCE_HOME}/tools" "${TARGET_HOME}/tools"
  sync_tree_copy_mode "${SOURCE_HOME}/skills/openclaw/codex-quota-manager" "${TARGET_HOME}/skills/openclaw/codex-quota-manager"
fi

sync_skill_copies
remove_repo_local_profile_dirs
normalize_script_permissions
refresh_legacy_profile_templates

printf 'SHARED_AGENT_HOME=%s\n' "${TARGET_HOME}"
