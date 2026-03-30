#!/usr/bin/env bash
set -euo pipefail

flow_canonical_skill_name() {
  printf '%s\n' "${AGENT_CONTROL_PLANE_SKILL_NAME:-agent-control-plane}"
}

flow_compat_skill_alias() {
  printf '%s\n' "${AGENT_CONTROL_PLANE_COMPAT_ALIAS:-}"
}

flow_export_env_alias_if_unset() {
  local target_name="${1:?target name required}"
  local source_name="${2:?source name required}"
  local source_value="${!source_name:-}"

  if [[ -n "${source_value}" && -z "${!target_name:-}" ]]; then
    export "${target_name}=${source_value}"
  fi
}

flow_export_compat_env_aliases() {
  flow_export_env_alias_if_unset F_LOSNING_FLOW_ROOT AGENT_CONTROL_PLANE_ROOT
  flow_export_env_alias_if_unset F_LOSNING_FLOW_ROOT ACP_ROOT
  flow_export_env_alias_if_unset F_LOSNING_REPO_SLUG ACP_REPO_SLUG
  flow_export_env_alias_if_unset F_LOSNING_REPO_ID ACP_REPO_ID
  flow_export_env_alias_if_unset F_LOSNING_GITHUB_REPOSITORY_ID ACP_GITHUB_REPOSITORY_ID
  flow_export_env_alias_if_unset F_LOSNING_REPO_ROOT ACP_REPO_ROOT
  flow_export_env_alias_if_unset F_LOSNING_AGENT_ROOT ACP_AGENT_ROOT
  flow_export_env_alias_if_unset F_LOSNING_AGENT_REPO_ROOT ACP_AGENT_REPO_ROOT
  flow_export_env_alias_if_unset F_LOSNING_WORKTREE_ROOT ACP_WORKTREE_ROOT
  flow_export_env_alias_if_unset F_LOSNING_RUNS_ROOT ACP_RUNS_ROOT
  flow_export_env_alias_if_unset F_LOSNING_STATE_ROOT ACP_STATE_ROOT
  flow_export_env_alias_if_unset F_LOSNING_HISTORY_ROOT ACP_HISTORY_ROOT
  flow_export_env_alias_if_unset F_LOSNING_MEMORY_DIR ACP_MEMORY_DIR
  flow_export_env_alias_if_unset F_LOSNING_RETAINED_REPO_ROOT ACP_RETAINED_REPO_ROOT
  flow_export_env_alias_if_unset F_LOSNING_VSCODE_WORKSPACE_FILE ACP_VSCODE_WORKSPACE_FILE
  flow_export_env_alias_if_unset F_LOSNING_CODING_WORKER ACP_CODING_WORKER
  flow_export_env_alias_if_unset F_LOSNING_CODEX_PROFILE_SAFE ACP_CODEX_PROFILE_SAFE
  flow_export_env_alias_if_unset F_LOSNING_CODEX_PROFILE_BYPASS ACP_CODEX_PROFILE_BYPASS
  flow_export_env_alias_if_unset F_LOSNING_CLAUDE_MODEL ACP_CLAUDE_MODEL
  flow_export_env_alias_if_unset F_LOSNING_CLAUDE_PERMISSION_MODE ACP_CLAUDE_PERMISSION_MODE
  flow_export_env_alias_if_unset F_LOSNING_CLAUDE_EFFORT ACP_CLAUDE_EFFORT
  flow_export_env_alias_if_unset F_LOSNING_CLAUDE_TIMEOUT_SECONDS ACP_CLAUDE_TIMEOUT_SECONDS
  flow_export_env_alias_if_unset F_LOSNING_CLAUDE_MAX_ATTEMPTS ACP_CLAUDE_MAX_ATTEMPTS
  flow_export_env_alias_if_unset F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS ACP_CLAUDE_RETRY_BACKOFF_SECONDS
  flow_export_env_alias_if_unset F_LOSNING_ISSUE_SESSION_PREFIX ACP_ISSUE_SESSION_PREFIX
  flow_export_env_alias_if_unset F_LOSNING_PR_SESSION_PREFIX ACP_PR_SESSION_PREFIX
  flow_export_env_alias_if_unset F_LOSNING_ISSUE_BRANCH_PREFIX ACP_ISSUE_BRANCH_PREFIX
  flow_export_env_alias_if_unset F_LOSNING_PR_WORKTREE_BRANCH_PREFIX ACP_PR_WORKTREE_BRANCH_PREFIX
  flow_export_env_alias_if_unset F_LOSNING_MANAGED_PR_BRANCH_GLOBS ACP_MANAGED_PR_BRANCH_GLOBS
  flow_export_env_alias_if_unset F_LOSNING_OPENCLAW_MODEL ACP_OPENCLAW_MODEL
  flow_export_env_alias_if_unset F_LOSNING_OPENCLAW_THINKING ACP_OPENCLAW_THINKING
  flow_export_env_alias_if_unset F_LOSNING_OPENCLAW_TIMEOUT_SECONDS ACP_OPENCLAW_TIMEOUT_SECONDS
  flow_export_env_alias_if_unset F_LOSNING_ALLOW_INFRA_CI_BYPASS ACP_ALLOW_INFRA_CI_BYPASS
  flow_export_env_alias_if_unset F_LOSNING_LOCAL_FIRST_PR_POLICY ACP_LOCAL_FIRST_PR_POLICY
  flow_export_env_alias_if_unset F_LOSNING_PR_RISK_CACHE_TTL_SECONDS ACP_PR_RISK_CACHE_TTL_SECONDS
  flow_export_env_alias_if_unset F_LOSNING_RETRY_COOLDOWNS ACP_RETRY_COOLDOWNS
  flow_export_env_alias_if_unset F_LOSNING_WORKTREE_LOCAL_INSTALL ACP_WORKTREE_LOCAL_INSTALL
  flow_export_env_alias_if_unset F_LOSNING_BOOTSTRAP_SCRIPT ACP_BOOTSTRAP_SCRIPT
  flow_export_env_alias_if_unset F_LOSNING_FLOW_HEARTBEAT_SCRIPT ACP_FLOW_HEARTBEAT_SCRIPT
  flow_export_env_alias_if_unset F_LOSNING_TIMEOUT_CHILD_PID_FILE ACP_TIMEOUT_CHILD_PID_FILE
  flow_export_env_alias_if_unset F_LOSNING_ISSUE_ID ACP_ISSUE_ID
  flow_export_env_alias_if_unset F_LOSNING_ISSUE_URL ACP_ISSUE_URL
  flow_export_env_alias_if_unset F_LOSNING_ISSUE_AUTOMERGE ACP_ISSUE_AUTOMERGE
  flow_export_env_alias_if_unset F_LOSNING_PR_NUMBER ACP_PR_NUMBER
  flow_export_env_alias_if_unset F_LOSNING_PR_URL ACP_PR_URL
  flow_export_env_alias_if_unset F_LOSNING_PR_HEAD_REF ACP_PR_HEAD_REF
}

flow_export_canonical_env_aliases() {
  flow_export_env_alias_if_unset ACP_ROOT F_LOSNING_FLOW_ROOT
  flow_export_env_alias_if_unset ACP_REPO_SLUG F_LOSNING_REPO_SLUG
  flow_export_env_alias_if_unset ACP_REPO_ID F_LOSNING_REPO_ID
  flow_export_env_alias_if_unset ACP_GITHUB_REPOSITORY_ID F_LOSNING_GITHUB_REPOSITORY_ID
  flow_export_env_alias_if_unset ACP_REPO_ROOT F_LOSNING_REPO_ROOT
  flow_export_env_alias_if_unset ACP_AGENT_ROOT F_LOSNING_AGENT_ROOT
  flow_export_env_alias_if_unset ACP_AGENT_REPO_ROOT F_LOSNING_AGENT_REPO_ROOT
  flow_export_env_alias_if_unset ACP_WORKTREE_ROOT F_LOSNING_WORKTREE_ROOT
  flow_export_env_alias_if_unset ACP_RUNS_ROOT F_LOSNING_RUNS_ROOT
  flow_export_env_alias_if_unset ACP_STATE_ROOT F_LOSNING_STATE_ROOT
  flow_export_env_alias_if_unset ACP_HISTORY_ROOT F_LOSNING_HISTORY_ROOT
  flow_export_env_alias_if_unset ACP_MEMORY_DIR F_LOSNING_MEMORY_DIR
  flow_export_env_alias_if_unset ACP_RETAINED_REPO_ROOT F_LOSNING_RETAINED_REPO_ROOT
  flow_export_env_alias_if_unset ACP_VSCODE_WORKSPACE_FILE F_LOSNING_VSCODE_WORKSPACE_FILE
  flow_export_env_alias_if_unset ACP_CODING_WORKER F_LOSNING_CODING_WORKER
  flow_export_env_alias_if_unset ACP_CODEX_PROFILE_SAFE F_LOSNING_CODEX_PROFILE_SAFE
  flow_export_env_alias_if_unset ACP_CODEX_PROFILE_BYPASS F_LOSNING_CODEX_PROFILE_BYPASS
  flow_export_env_alias_if_unset ACP_CLAUDE_MODEL F_LOSNING_CLAUDE_MODEL
  flow_export_env_alias_if_unset ACP_CLAUDE_PERMISSION_MODE F_LOSNING_CLAUDE_PERMISSION_MODE
  flow_export_env_alias_if_unset ACP_CLAUDE_EFFORT F_LOSNING_CLAUDE_EFFORT
  flow_export_env_alias_if_unset ACP_CLAUDE_TIMEOUT_SECONDS F_LOSNING_CLAUDE_TIMEOUT_SECONDS
  flow_export_env_alias_if_unset ACP_CLAUDE_MAX_ATTEMPTS F_LOSNING_CLAUDE_MAX_ATTEMPTS
  flow_export_env_alias_if_unset ACP_CLAUDE_RETRY_BACKOFF_SECONDS F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS
  flow_export_env_alias_if_unset ACP_ISSUE_SESSION_PREFIX F_LOSNING_ISSUE_SESSION_PREFIX
  flow_export_env_alias_if_unset ACP_PR_SESSION_PREFIX F_LOSNING_PR_SESSION_PREFIX
  flow_export_env_alias_if_unset ACP_ISSUE_BRANCH_PREFIX F_LOSNING_ISSUE_BRANCH_PREFIX
  flow_export_env_alias_if_unset ACP_PR_WORKTREE_BRANCH_PREFIX F_LOSNING_PR_WORKTREE_BRANCH_PREFIX
  flow_export_env_alias_if_unset ACP_MANAGED_PR_BRANCH_GLOBS F_LOSNING_MANAGED_PR_BRANCH_GLOBS
  flow_export_env_alias_if_unset ACP_OPENCLAW_MODEL F_LOSNING_OPENCLAW_MODEL
  flow_export_env_alias_if_unset ACP_OPENCLAW_THINKING F_LOSNING_OPENCLAW_THINKING
  flow_export_env_alias_if_unset ACP_OPENCLAW_TIMEOUT_SECONDS F_LOSNING_OPENCLAW_TIMEOUT_SECONDS
  flow_export_env_alias_if_unset ACP_ALLOW_INFRA_CI_BYPASS F_LOSNING_ALLOW_INFRA_CI_BYPASS
  flow_export_env_alias_if_unset ACP_LOCAL_FIRST_PR_POLICY F_LOSNING_LOCAL_FIRST_PR_POLICY
  flow_export_env_alias_if_unset ACP_PR_RISK_CACHE_TTL_SECONDS F_LOSNING_PR_RISK_CACHE_TTL_SECONDS
  flow_export_env_alias_if_unset ACP_RETRY_COOLDOWNS F_LOSNING_RETRY_COOLDOWNS
  flow_export_env_alias_if_unset ACP_WORKTREE_LOCAL_INSTALL F_LOSNING_WORKTREE_LOCAL_INSTALL
  flow_export_env_alias_if_unset ACP_BOOTSTRAP_SCRIPT F_LOSNING_BOOTSTRAP_SCRIPT
  flow_export_env_alias_if_unset ACP_FLOW_HEARTBEAT_SCRIPT F_LOSNING_FLOW_HEARTBEAT_SCRIPT
  flow_export_env_alias_if_unset ACP_TIMEOUT_CHILD_PID_FILE F_LOSNING_TIMEOUT_CHILD_PID_FILE
  flow_export_env_alias_if_unset ACP_ISSUE_ID F_LOSNING_ISSUE_ID
  flow_export_env_alias_if_unset ACP_ISSUE_URL F_LOSNING_ISSUE_URL
  flow_export_env_alias_if_unset ACP_ISSUE_AUTOMERGE F_LOSNING_ISSUE_AUTOMERGE
  flow_export_env_alias_if_unset ACP_PR_NUMBER F_LOSNING_PR_NUMBER
  flow_export_env_alias_if_unset ACP_PR_URL F_LOSNING_PR_URL
  flow_export_env_alias_if_unset ACP_PR_HEAD_REF F_LOSNING_PR_HEAD_REF
}

flow_export_project_env_aliases() {
  flow_export_compat_env_aliases
  flow_export_canonical_env_aliases
}

flow_is_skill_root() {
  local candidate="${1:-}"
  [[ -n "${candidate}" ]] || return 1
  [[ -d "${candidate}" ]] || return 1
  [[ -d "${candidate}/tools/bin" ]] || return 1

  if [[ -f "${candidate}/SKILL.md" \
    || -f "${candidate}/assets/workflow-catalog.json" ]]; then
    return 0
  fi

  [[ -d "${candidate}/bin" || -d "${candidate}/hooks" ]]
}

flow_print_dir() {
  local candidate="${1:-}"
  [[ -n "${candidate}" ]] || return 1
  (cd "${candidate}" && pwd -P)
}

resolve_flow_skill_dir() {
  local script_path="${1:-}"
  local candidate=""
  local skill_name=""

  for candidate in \
    "${AGENT_CONTROL_PLANE_ROOT:-}" \
    "${ACP_ROOT:-}" \
    "${F_LOSNING_FLOW_ROOT:-}" \
    "${AGENT_FLOW_SKILL_ROOT:-}"; do
    if flow_is_skill_root "${candidate}"; then
      flow_print_dir "${candidate}"
      return 0
    fi
  done

  if [[ -n "${script_path}" ]]; then
    candidate="$(
      cd "$(dirname "${script_path}")/../.." 2>/dev/null && pwd -P
    )" || candidate=""
    if flow_is_skill_root "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if [[ -n "${SHARED_AGENT_HOME:-}" ]]; then
    for skill_name in "$(flow_canonical_skill_name)" "$(flow_compat_skill_alias)"; do
      candidate="${SHARED_AGENT_HOME}/skills/openclaw/${skill_name}"
      if flow_is_skill_root "${candidate}"; then
        flow_print_dir "${candidate}"
        return 0
      fi
    done
  fi

  for skill_name in "$(flow_canonical_skill_name)" "$(flow_compat_skill_alias)"; do
    candidate="${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}/runtime-home/skills/openclaw/${skill_name}"
    if flow_is_skill_root "${candidate}"; then
      flow_print_dir "${candidate}"
      return 0
    fi
  done

  echo "unable to resolve agent control plane root" >&2
  return 1
}

resolve_shared_agent_home() {
  local flow_root="${1:-}"

  if [[ -n "${SHARED_AGENT_HOME:-}" ]]; then
    flow_print_dir "${SHARED_AGENT_HOME}"
    return 0
  fi

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_print_dir "${flow_root}/../../.."
}

resolve_runtime_home() {
  flow_print_dir "${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}/runtime-home"
}

resolve_runtime_canonical_skill_dir() {
  local runtime_home
  runtime_home="$(resolve_runtime_home)"
  printf '%s/skills/openclaw/%s\n' "${runtime_home}" "$(flow_canonical_skill_name)"
}

resolve_runtime_compat_skill_dir() {
  local runtime_home
  local compat_alias=""
  runtime_home="$(resolve_runtime_home)"
  compat_alias="$(flow_compat_skill_alias)"
  if [[ -z "${compat_alias}" ]]; then
    printf '\n'
    return 0
  fi
  printf '%s/skills/openclaw/%s\n' "${runtime_home}" "${compat_alias}"
}

resolve_runtime_skill_dir() {
  local candidate=""

  for candidate in \
    "$(resolve_runtime_canonical_skill_dir)" \
    "$(resolve_runtime_compat_skill_dir)"; do
    if [[ -e "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  resolve_runtime_compat_skill_dir
}

resolve_source_canonical_skill_dir() {
  local shared_home="${1:-}"
  if [[ -z "${shared_home}" ]]; then
    shared_home="$(resolve_shared_agent_home)"
  fi
  printf '%s/skills/openclaw/%s\n' "${shared_home}" "$(flow_canonical_skill_name)"
}

resolve_source_compat_skill_dir() {
  local shared_home="${1:-}"
  local compat_alias=""
  if [[ -z "${shared_home}" ]]; then
    shared_home="$(resolve_shared_agent_home)"
  fi
  compat_alias="$(flow_compat_skill_alias)"
  if [[ -z "${compat_alias}" ]]; then
    printf '\n'
    return 0
  fi
  printf '%s/skills/openclaw/%s\n' "${shared_home}" "${compat_alias}"
}

flow_export_project_env_aliases
