#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
PROFILE_REGISTRY_ROOT="$(resolve_flow_profile_registry_root)"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
# Do NOT export execution env for the current profile here — render-flow-config
# is meant to render the SELECTED profile's config (via CONFIG_YAML), and exporting
# the ambient profile's vars into the shell causes config_or_env to silently override
# per-profile YAML with defaults from the current resident worker's own config.
# Also, ambient env vars from the shell are cleared below so they don't leak into
# profile-smoke or other callers.
for _clean in ACP_CODING_WORKER ACP_OPENCLAW_MODEL ACP_CLAUDE_MODEL \
  ACP_CLAUDE_TIMEOUT_SECONDS ACP_CLAUDE_MAX_ATTEMPTS ACP_CLAUDE_RETRY_BACKOFF_SECONDS \
  ACP_OPENCLAW_THINKING ACP_OPENCLAW_TIMEOUT_SECONDS \
  F_LOSNING_CODING_WORKER F_LOSNING_OPENCLAW_MODEL F_LOSNING_CLAUDE_MODEL \
  F_LOSNING_CLAUDE_TIMEOUT_SECONDS F_LOSNING_CLAUDE_MAX_ATTEMPTS F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS \
  F_LOSNING_OPENCLAW_THINKING F_LOSNING_OPENCLAW_TIMEOUT_SECONDS \
  CODING_WORKER; do
  unset "${_clean}" 2>/dev/null || true
done
unset _clean
AVAILABLE_PROFILES="$(flow_list_profile_ids "${FLOW_SKILL_DIR}" | paste -sd, -)"
INSTALLED_PROFILES="$(flow_list_installed_profile_ids | paste -sd, -)"
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
PROFILE_SELECTION_MODE="$(flow_profile_selection_mode "${FLOW_SKILL_DIR}")"
PROFILE_SELECTION_HINT="$(flow_profile_selection_hint "${FLOW_SKILL_DIR}")"
PROFILE_NOTES="$(flow_resolve_profile_notes_file "${CONFIG_YAML}")"

config_or_env() {
  local env_names="${1:?env names required}"
  local config_key="${2:-}"
  local env_name=""
  local value=""

  for env_name in ${env_names}; do
    value="${!env_name:-}"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done

  if [[ -n "${config_key}" && -f "${CONFIG_YAML}" ]]; then
    flow_config_get "${CONFIG_YAML}" "${config_key}"
    return 0
  fi

  printf '\n'
}

printf 'FLOW_SKILL_DIR=%s\n' "${FLOW_SKILL_DIR}"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "${PROFILE_REGISTRY_ROOT}"
printf 'CONFIG_YAML=%s\n' "${CONFIG_YAML}"
printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
printf 'PROFILE_SELECTION_MODE=%s\n' "${PROFILE_SELECTION_MODE}"
if [[ -n "${PROFILE_SELECTION_HINT}" ]]; then
  printf 'PROFILE_SELECTION_HINT=%s\n' "${PROFILE_SELECTION_HINT}"
fi
printf 'AVAILABLE_PROFILES=%s\n' "${AVAILABLE_PROFILES}"
printf 'INSTALLED_PROFILES=%s\n' "${INSTALLED_PROFILES}"
printf 'PROFILE_NOTES=%s\n' "${PROFILE_NOTES}"
if [[ -f "${PROFILE_NOTES}" ]]; then
  printf 'PROFILE_NOTES_EXISTS=yes\n'
else
  printf 'PROFILE_NOTES_EXISTS=no\n'
fi
printf 'EFFECTIVE_REPO_ROOT=%s\n' "$(config_or_env 'ACP_REPO_ROOT F_LOSNING_REPO_ROOT' repo.root)"
printf 'EFFECTIVE_AGENT_REPO_ROOT=%s\n' "$(config_or_env 'ACP_AGENT_REPO_ROOT F_LOSNING_AGENT_REPO_ROOT' runtime.agent_repo_root)"
printf 'EFFECTIVE_WORKTREE_ROOT=%s\n' "$(config_or_env 'ACP_WORKTREE_ROOT F_LOSNING_WORKTREE_ROOT' runtime.worktree_root)"
printf 'EFFECTIVE_RUNS_ROOT=%s\n' "$(config_or_env 'ACP_RUNS_ROOT F_LOSNING_RUNS_ROOT' runtime.runs_root)"
printf 'EFFECTIVE_STATE_ROOT=%s\n' "$(config_or_env 'ACP_STATE_ROOT F_LOSNING_STATE_ROOT' runtime.state_root)"
printf 'EFFECTIVE_RETAINED_REPO_ROOT=%s\n' "$(config_or_env 'ACP_RETAINED_REPO_ROOT F_LOSNING_RETAINED_REPO_ROOT' runtime.retained_repo_root)"
printf 'EFFECTIVE_VSCODE_WORKSPACE_FILE=%s\n' "$(config_or_env 'ACP_VSCODE_WORKSPACE_FILE F_LOSNING_VSCODE_WORKSPACE_FILE' runtime.vscode_workspace_file)"
printf 'EFFECTIVE_CODING_WORKER=%s\n' "$(config_or_env 'ACP_CODING_WORKER F_LOSNING_CODING_WORKER' execution.coding_worker)"
printf 'EFFECTIVE_PROVIDER_QUOTA_COOLDOWNS=%s\n' "$(config_or_env 'ACP_PROVIDER_QUOTA_COOLDOWNS F_LOSNING_PROVIDER_QUOTA_COOLDOWNS' execution.provider_quota.cooldowns)"
printf 'EFFECTIVE_PROVIDER_POOL_ORDER=%s\n' "$(config_or_env 'ACP_PROVIDER_POOL_ORDER F_LOSNING_PROVIDER_POOL_ORDER' execution.provider_pool_order)"
printf 'EFFECTIVE_PROVIDER_POOL_NAME=%s\n' "$(config_or_env 'ACP_ACTIVE_PROVIDER_POOL_NAME F_LOSNING_ACTIVE_PROVIDER_POOL_NAME')"
printf 'EFFECTIVE_PROVIDER_POOL_BACKEND=%s\n' "$(config_or_env 'ACP_ACTIVE_PROVIDER_BACKEND F_LOSNING_ACTIVE_PROVIDER_BACKEND')"
printf 'EFFECTIVE_PROVIDER_POOL_MODEL=%s\n' "$(config_or_env 'ACP_ACTIVE_PROVIDER_MODEL F_LOSNING_ACTIVE_PROVIDER_MODEL')"
printf 'EFFECTIVE_PROVIDER_POOL_KEY=%s\n' "$(config_or_env 'ACP_ACTIVE_PROVIDER_KEY F_LOSNING_ACTIVE_PROVIDER_KEY')"
printf 'EFFECTIVE_PROVIDER_POOLS_EXHAUSTED=%s\n' "$(config_or_env 'ACP_PROVIDER_POOLS_EXHAUSTED F_LOSNING_PROVIDER_POOLS_EXHAUSTED')"
printf 'EFFECTIVE_PROVIDER_POOL_SELECTION_REASON=%s\n' "$(config_or_env 'ACP_PROVIDER_POOL_SELECTION_REASON F_LOSNING_PROVIDER_POOL_SELECTION_REASON')"
printf 'EFFECTIVE_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH=%s\n' "$(config_or_env 'ACP_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH')"
printf 'EFFECTIVE_PROVIDER_POOL_NEXT_ATTEMPT_AT=%s\n' "$(config_or_env 'ACP_PROVIDER_POOL_NEXT_ATTEMPT_AT F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_AT')"
printf 'EFFECTIVE_PROVIDER_POOL_LAST_REASON=%s\n' "$(config_or_env 'ACP_PROVIDER_POOL_LAST_REASON F_LOSNING_PROVIDER_POOL_LAST_REASON')"
printf 'EFFECTIVE_CODEX_PROFILE_SAFE=%s\n' "$(config_or_env 'ACP_CODEX_PROFILE_SAFE F_LOSNING_CODEX_PROFILE_SAFE' execution.safe_profile)"
printf 'EFFECTIVE_CODEX_PROFILE_BYPASS=%s\n' "$(config_or_env 'ACP_CODEX_PROFILE_BYPASS F_LOSNING_CODEX_PROFILE_BYPASS' execution.bypass_profile)"
printf 'EFFECTIVE_CLAUDE_MODEL=%s\n' "$(config_or_env 'ACP_CLAUDE_MODEL F_LOSNING_CLAUDE_MODEL' execution.claude.model)"
printf 'EFFECTIVE_CLAUDE_PERMISSION_MODE=%s\n' "$(config_or_env 'ACP_CLAUDE_PERMISSION_MODE F_LOSNING_CLAUDE_PERMISSION_MODE' execution.claude.permission_mode)"
printf 'EFFECTIVE_CLAUDE_EFFORT=%s\n' "$(config_or_env 'ACP_CLAUDE_EFFORT F_LOSNING_CLAUDE_EFFORT' execution.claude.effort)"
printf 'EFFECTIVE_CLAUDE_TIMEOUT_SECONDS=%s\n' "$(config_or_env 'ACP_CLAUDE_TIMEOUT_SECONDS F_LOSNING_CLAUDE_TIMEOUT_SECONDS' execution.claude.timeout_seconds)"
printf 'EFFECTIVE_CLAUDE_MAX_ATTEMPTS=%s\n' "$(config_or_env 'ACP_CLAUDE_MAX_ATTEMPTS F_LOSNING_CLAUDE_MAX_ATTEMPTS' execution.claude.max_attempts)"
printf 'EFFECTIVE_CLAUDE_RETRY_BACKOFF_SECONDS=%s\n' "$(config_or_env 'ACP_CLAUDE_RETRY_BACKOFF_SECONDS F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS' execution.claude.retry_backoff_seconds)"
printf 'EFFECTIVE_OPENCLAW_MODEL=%s\n' "$(config_or_env 'ACP_OPENCLAW_MODEL F_LOSNING_OPENCLAW_MODEL' execution.openclaw.model)"
printf 'EFFECTIVE_OPENCLAW_THINKING=%s\n' "$(config_or_env 'ACP_OPENCLAW_THINKING F_LOSNING_OPENCLAW_THINKING' execution.openclaw.thinking)"
printf 'EFFECTIVE_OPENCLAW_TIMEOUT_SECONDS=%s\n' "$(config_or_env 'ACP_OPENCLAW_TIMEOUT_SECONDS F_LOSNING_OPENCLAW_TIMEOUT_SECONDS' execution.openclaw.timeout_seconds)"
