#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"
flow_export_project_env_aliases

flow_explicit_github_repo_id() {
  local requested_repo_slug="${1:-}"
  local configured_repo_slug="${ACP_REPO_SLUG:-${F_LOSNING_REPO_SLUG:-}}"
  local explicit_repo_id="${ACP_REPO_ID:-${F_LOSNING_REPO_ID:-${ACP_GITHUB_REPOSITORY_ID:-${F_LOSNING_GITHUB_REPOSITORY_ID:-}}}}"

  [[ -n "${explicit_repo_id}" ]] || return 1
  if [[ -n "${requested_repo_slug}" && -n "${configured_repo_slug}" && "${configured_repo_slug}" != "${requested_repo_slug}" ]]; then
    return 1
  fi

  printf '%s\n' "${explicit_repo_id}"
}

flow_explicit_profile_id() {
  printf '%s\n' "${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-}}"
}

resolve_flow_profile_registry_root() {
  local platform_home="${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}"
  printf '%s\n' "${AGENT_CONTROL_PLANE_PROFILE_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${platform_home}/control-plane/profiles}}"
}

flow_list_profiles_in_root() {
  local profiles_root="${1:-}"
  local profile_file=""
  local profile_id=""

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile_file; do
    [[ -n "${profile_file}" ]] || continue
    profile_id="$(basename "$(dirname "${profile_file}")")"
    [[ -n "${profile_id}" ]] || continue
    printf '%s\n' "${profile_id}"
  done < <(find "${profiles_root}" -mindepth 2 -maxdepth 2 -type f -name 'control-plane.yaml' 2>/dev/null | sort)
}

flow_list_installed_profile_ids() {
  flow_list_profiles_in_root "$(resolve_flow_profile_registry_root)"
}

flow_find_profile_dir_by_id() {
  local flow_root="${1:-}"
  local profile_id="${2:?profile id required}"
  local registry_root=""
  local candidate=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  registry_root="$(resolve_flow_profile_registry_root)"
  candidate="${registry_root}/${profile_id}"
  if [[ -f "${candidate}/control-plane.yaml" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s/%s\n' "${registry_root}" "${profile_id}"
}

flow_profile_count() {
  local flow_root="${1:-}"

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_list_profile_ids "${flow_root}" | awk 'NF { count += 1 } END { print count + 0 }'
}

flow_default_profile_id() {
  local flow_root="${1:-}"
  local preferred_profile="${AGENT_CONTROL_PLANE_DEFAULT_PROFILE_ID:-${ACP_DEFAULT_PROFILE_ID:-${AGENT_PROJECT_DEFAULT_PROFILE_ID:-}}}"
  local candidate=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  for candidate in "${preferred_profile}" "default"; do
    [[ -n "${candidate}" ]] || continue
    if [[ -f "$(flow_find_profile_dir_by_id "${flow_root}" "${candidate}")/control-plane.yaml" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(flow_list_profile_ids "${flow_root}" | grep -v '^demo$' | head -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  candidate="$(flow_list_profile_ids "${flow_root}" | head -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf 'default\n'
}

flow_profile_selection_mode() {
  local flow_root="${1:-}"
  local explicit_profile=""
  local profile_count="0"

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  explicit_profile="$(flow_explicit_profile_id)"
  if [[ -n "${explicit_profile}" ]]; then
    printf 'explicit\n'
    return 0
  fi

  profile_count="$(flow_profile_count "${flow_root}")"
  if [[ "${profile_count}" -gt 1 ]]; then
    printf 'implicit-default\n'
    return 0
  fi

  printf 'single-profile-default\n'
}

flow_profile_selection_hint() {
  local flow_root="${1:-}"
  local mode=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  mode="$(flow_profile_selection_mode "${flow_root}")"
  if [[ "${mode}" == "implicit-default" ]]; then
    printf 'Set ACP_PROJECT_ID=<id> or AGENT_PROJECT_ID=<id> when multiple available profiles exist.\n'
  fi
}

flow_profile_guard_message() {
  local flow_root="${1:-}"
  local command_name="${2:-this command}"
  local hint=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  hint="$(flow_profile_selection_hint "${flow_root}")"
  printf 'explicit profile selection required for %s when multiple available profiles exist.\n' "${command_name}"
  if [[ -n "${hint}" ]]; then
    printf '%s\n' "${hint}"
  fi
}

flow_require_explicit_profile_selection() {
  local flow_root="${1:-}"
  local command_name="${2:-this command}"

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ "${ACP_ALLOW_IMPLICIT_PROFILE_SELECTION:-0}" == "1" ]]; then
    return 0
  fi

  if [[ "$(flow_profile_selection_mode "${flow_root}")" == "implicit-default" ]]; then
    flow_profile_guard_message "${flow_root}" "${command_name}" >&2
    return 1
  fi

  return 0
}

resolve_flow_config_yaml() {
  local script_path="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
  local flow_root
  local profile_id=""
  local candidate=""
  flow_root="$(resolve_flow_skill_dir "${script_path}")"
  profile_id="${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-$(flow_default_profile_id "${flow_root}")}}"

  for candidate in \
    "${AGENT_CONTROL_PLANE_CONFIG:-}" \
    "${ACP_CONFIG:-}" \
    "${AGENT_PROJECT_CONFIG_PATH:-}" \
    "${F_LOSNING_FLOW_CONFIG:-}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(flow_find_profile_dir_by_id "${flow_root}" "${profile_id}")/control-plane.yaml"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s\n' "${candidate}"
}

flow_list_profile_ids() {
  local flow_root="${1:-}"
  local found_any=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  found_any="$(
    {
      flow_list_installed_profile_ids
    } | awk 'NF { print }' | sort -u
  )"

  if [[ -z "${found_any}" ]]; then
    return 0
  fi

  printf '%s\n' "${found_any}"
}

flow_git_remote_repo_slug() {
  local repo_root="${1:-}"
  local remote_name="${2:-origin}"
  local remote_url=""
  local normalized=""

  [[ -n "${repo_root}" && -d "${repo_root}" ]] || return 1
  remote_url="$(git -C "${repo_root}" remote get-url "${remote_name}" 2>/dev/null || true)"
  [[ -n "${remote_url}" ]] || return 1

  normalized="${remote_url%.git}"
  case "${normalized}" in
    ssh://*@*/*)
      normalized="${normalized#ssh://}"
      normalized="${normalized#*@}"
      normalized="${normalized#*/}"
      ;;
    *@*:*/*)
      normalized="${normalized#*@}"
      normalized="${normalized#*:}"
      ;;
    https://*/*|http://*/*)
      normalized="${normalized#http://}"
      normalized="${normalized#https://}"
      normalized="${normalized#*/}"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "${normalized}" == */*/* ]]; then
    normalized="${normalized#*/}"
  fi

  if [[ "${normalized}" =~ ^[^/]+/[^/]+$ ]]; then
    printf '%s\n' "${normalized}"
    return 0
  fi

  return 1
}

flow_git_has_remote() {
  local repo_root="${1:-}"
  local remote_name="${2:-}"

  [[ -n "${repo_root}" && -d "${repo_root}" && -n "${remote_name}" ]] || return 1
  git -C "${repo_root}" remote get-url "${remote_name}" >/dev/null 2>&1
}

flow_resolve_forge_primary_remote() {
  local repo_root="${1:-}"
  local repo_slug="${2:-}"
  local remote_name=""
  local override="${ACP_SOURCE_SYNC_REMOTE:-${F_LOSNING_SOURCE_SYNC_REMOTE:-}}"
  local forge_provider=""

  [[ -n "${repo_root}" && -d "${repo_root}" ]] || return 1

  if [[ -n "${override}" ]] && flow_git_has_remote "${repo_root}" "${override}"; then
    printf '%s\n' "${override}"
    return 0
  fi

  forge_provider="$(flow_forge_provider)"
  case "${forge_provider}" in
    gitea)
      if flow_git_has_remote "${repo_root}" "gitea"; then
        printf 'gitea\n'
        return 0
      fi
      ;;
    github)
      if flow_git_has_remote "${repo_root}" "origin"; then
        printf 'origin\n'
        return 0
      fi
      ;;
  esac

  if [[ -n "${repo_slug}" ]]; then
    while IFS= read -r remote_name; do
      [[ -n "${remote_name}" ]] || continue
      if [[ "$(flow_git_remote_repo_slug "${repo_root}" "${remote_name}" 2>/dev/null || true)" == "${repo_slug}" ]]; then
        printf '%s\n' "${remote_name}"
        return 0
      fi
    done < <(git -C "${repo_root}" remote)
  fi

  for remote_name in origin gitea; do
    if flow_git_has_remote "${repo_root}" "${remote_name}"; then
      printf '%s\n' "${remote_name}"
      return 0
    fi
  done

  return 1
}

