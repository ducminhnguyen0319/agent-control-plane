flow_provider_pool_state_get() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"
  local backend=""
  local model=""
  local state_root=""
  local provider_key=""
  local state_file=""
  local attempts="0"
  local next_attempt_epoch="0"
  local next_attempt_at=""
  local last_reason=""
  local updated_at=""
  local ready="yes"
  local valid="yes"
  local now_epoch=""
  local safe_profile=""
  local bypass_profile=""
  local claude_model=""
  local claude_permission_mode=""
  local claude_effort=""
  local claude_timeout_seconds=""
  local claude_max_attempts=""
  local claude_retry_backoff_seconds=""
  local openclaw_model=""
  local openclaw_thinking=""
  local openclaw_timeout_seconds=""
  local ollama_model=""
  local ollama_base_url=""
  local ollama_timeout_seconds=""
  local pi_model=""
  local pi_thinking=""
  local pi_timeout_seconds=""
  local opencode_model=""
  local opencode_timeout_seconds=""
  local kilo_model=""
  local kilo_timeout_seconds=""

  backend="$(flow_provider_pool_backend "${config_file}" "${pool_name}")"
  safe_profile="$(flow_provider_pool_safe_profile "${config_file}" "${pool_name}")"
  bypass_profile="$(flow_provider_pool_bypass_profile "${config_file}" "${pool_name}")"
  claude_model="$(flow_provider_pool_claude_model "${config_file}" "${pool_name}")"
  claude_permission_mode="$(flow_provider_pool_claude_permission_mode "${config_file}" "${pool_name}")"
  claude_effort="$(flow_provider_pool_claude_effort "${config_file}" "${pool_name}")"
  claude_timeout_seconds="$(flow_provider_pool_claude_timeout_seconds "${config_file}" "${pool_name}")"
  claude_max_attempts="$(flow_provider_pool_claude_max_attempts "${config_file}" "${pool_name}")"
  claude_retry_backoff_seconds="$(flow_provider_pool_claude_retry_backoff_seconds "${config_file}" "${pool_name}")"
  openclaw_model="$(flow_provider_pool_openclaw_model "${config_file}" "${pool_name}")"
  openclaw_thinking="$(flow_provider_pool_openclaw_thinking "${config_file}" "${pool_name}")"
  openclaw_timeout_seconds="$(flow_provider_pool_openclaw_timeout_seconds "${config_file}" "${pool_name}")"
  ollama_model="$(flow_provider_pool_ollama_model "${config_file}" "${pool_name}")"
  ollama_base_url="$(flow_provider_pool_ollama_base_url "${config_file}" "${pool_name}")"
  ollama_timeout_seconds="$(flow_provider_pool_ollama_timeout_seconds "${config_file}" "${pool_name}")"
  pi_model="$(flow_provider_pool_pi_model "${config_file}" "${pool_name}")"
  pi_thinking="$(flow_provider_pool_pi_thinking "${config_file}" "${pool_name}")"
  pi_timeout_seconds="$(flow_provider_pool_pi_timeout_seconds "${config_file}" "${pool_name}")"
  opencode_model="$(flow_provider_pool_opencode_model "${config_file}" "${pool_name}")"
  opencode_timeout_seconds="$(flow_provider_pool_opencode_timeout_seconds "${config_file}" "${pool_name}")"
  kilo_model="$(flow_provider_pool_kilo_model "${config_file}" "${pool_name}")"
  kilo_timeout_seconds="$(flow_provider_pool_kilo_timeout_seconds "${config_file}" "${pool_name}")"
  model="$(flow_provider_pool_model_identity "${config_file}" "${pool_name}")"

  case "${backend}" in
    codex)
      [[ -n "${safe_profile}" && -n "${bypass_profile}" ]] || valid="no"
      ;;
    claude)
      [[ -n "${claude_model}" && -n "${claude_permission_mode}" && -n "${claude_effort}" && -n "${claude_timeout_seconds}" && -n "${claude_max_attempts}" && -n "${claude_retry_backoff_seconds}" ]] || valid="no"
      ;;
    openclaw)
      [[ -n "${openclaw_model}" && -n "${openclaw_thinking}" && -n "${openclaw_timeout_seconds}" ]] || valid="no"
      ;;
    ollama)
      [[ -n "${ollama_model}" ]] || valid="no"
      ;;
    pi)
      [[ -n "${pi_model}" ]] || valid="no"
      ;;
    opencode)
      [[ -n "${opencode_model}" && -n "${opencode_timeout_seconds}" ]] || valid="no"
      ;;
    kilo)
      [[ -n "${kilo_model}" && -n "${kilo_timeout_seconds}" ]] || valid="no"
      ;;
    *)
      valid="no"
      ;;
  esac

  if [[ "${valid}" == "yes" && -n "${model}" ]]; then
    state_root="$(flow_resolve_state_root "${config_file}")"
    provider_key="$(flow_sanitize_provider_key "${backend}-${model}")"
    state_file="${state_root}/retries/providers/${provider_key}.env"

    if [[ -f "${state_file}" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "${state_file}"
      set +a
      attempts="${ATTEMPTS:-0}"
      next_attempt_epoch="${NEXT_ATTEMPT_EPOCH:-0}"
      next_attempt_at="${NEXT_ATTEMPT_AT:-}"
      last_reason="${LAST_REASON:-}"
      updated_at="${UPDATED_AT:-}"
    fi

    now_epoch="$(date +%s)"
    if [[ "${next_attempt_epoch}" =~ ^[0-9]+$ ]] && (( next_attempt_epoch > now_epoch )); then
      ready="no"
    fi
  else
    ready="no"
  fi

  printf 'POOL_NAME=%s\n' "${pool_name}"
  printf 'VALID=%s\n' "${valid}"
  printf 'BACKEND=%s\n' "${backend}"
  printf 'MODEL=%s\n' "${model}"
  printf 'PROVIDER_KEY=%s\n' "${provider_key}"
  printf 'ATTEMPTS=%s\n' "${attempts}"
  printf 'NEXT_ATTEMPT_EPOCH=%s\n' "${next_attempt_epoch}"
  printf 'NEXT_ATTEMPT_AT=%s\n' "${next_attempt_at}"
  printf 'READY=%s\n' "${ready}"
  printf 'LAST_REASON=%s\n' "${last_reason}"
  printf 'UPDATED_AT=%s\n' "${updated_at}"
  printf 'SAFE_PROFILE=%s\n' "${safe_profile}"
  printf 'BYPASS_PROFILE=%s\n' "${bypass_profile}"
  printf 'CLAUDE_MODEL=%s\n' "${claude_model}"
  printf 'CLAUDE_PERMISSION_MODE=%s\n' "${claude_permission_mode}"
  printf 'CLAUDE_EFFORT=%s\n' "${claude_effort}"
  printf 'CLAUDE_TIMEOUT_SECONDS=%s\n' "${claude_timeout_seconds}"
  printf 'CLAUDE_MAX_ATTEMPTS=%s\n' "${claude_max_attempts}"
  printf 'CLAUDE_RETRY_BACKOFF_SECONDS=%s\n' "${claude_retry_backoff_seconds}"
  printf 'OPENCLAW_MODEL=%s\n' "${openclaw_model}"
  printf 'OPENCLAW_THINKING=%s\n' "${openclaw_thinking}"
  printf 'OPENCLAW_TIMEOUT_SECONDS=%s\n' "${openclaw_timeout_seconds}"
  printf 'OLLAMA_MODEL=%s\n' "${ollama_model}"
  printf 'OLLAMA_BASE_URL=%s\n' "${ollama_base_url}"
  printf 'OLLAMA_TIMEOUT_SECONDS=%s\n' "${ollama_timeout_seconds}"
  printf 'PI_MODEL=%s\n' "${pi_model}"
  printf 'PI_THINKING=%s\n' "${pi_thinking}"
  printf 'PI_TIMEOUT_SECONDS=%s\n' "${pi_timeout_seconds}"
  printf 'OPENCODE_MODEL=%s\n' "${opencode_model}"
  printf 'OPENCODE_TIMEOUT_SECONDS=%s\n' "${opencode_timeout_seconds}"
  printf 'KILO_MODEL=%s\n' "${kilo_model}"
  printf 'KILO_TIMEOUT_SECONDS=%s\n' "${kilo_timeout_seconds}"
}

flow_selected_provider_pool_env() {
  local config_file="${1:-}"
  local pool_name=""
  local candidate=""
  local candidate_valid=""
  local candidate_ready=""
  local candidate_next_epoch="0"
  local exhausted_candidate=""
  local exhausted_epoch=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if ! flow_provider_pools_enabled "${config_file}"; then
    return 1
  fi

  while IFS= read -r pool_name; do
    [[ -n "${pool_name}" ]] || continue
    candidate="$(flow_provider_pool_state_get "${config_file}" "${pool_name}")"
    candidate_valid="$(awk -F= '/^VALID=/{print $2}' <<<"${candidate}")"
    [[ "${candidate_valid}" == "yes" ]] || continue

    candidate_ready="$(awk -F= '/^READY=/{print $2}' <<<"${candidate}")"
    if [[ "${candidate_ready}" == "yes" ]]; then
      printf '%s\n' "${candidate}"
      printf 'POOLS_EXHAUSTED=no\n'
      printf 'SELECTION_REASON=ready\n'
      return 0
    fi

    candidate_next_epoch="$(awk -F= '/^NEXT_ATTEMPT_EPOCH=/{print $2}' <<<"${candidate}")"
    if [[ -z "${exhausted_candidate}" ]]; then
      exhausted_candidate="${candidate}"
      exhausted_epoch="${candidate_next_epoch}"
      continue
    fi

    if [[ "${candidate_next_epoch}" =~ ^[0-9]+$ && "${exhausted_epoch}" =~ ^[0-9]+$ ]] && (( candidate_next_epoch < exhausted_epoch )); then
      exhausted_candidate="${candidate}"
      exhausted_epoch="${candidate_next_epoch}"
    fi
  done < <(flow_provider_pool_names "${config_file}")

  [[ -n "${exhausted_candidate}" ]] || return 1

  printf '%s\n' "${exhausted_candidate}"
  printf 'POOLS_EXHAUSTED=yes\n'
  printf 'SELECTION_REASON=all-cooldown\n'
}

flow_resolve_issue_session_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_issue_session_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_ISSUE_SESSION_PREFIX F_LOSNING_ISSUE_SESSION_PREFIX" "session_naming.issue_prefix" "${default_value}"
}

flow_resolve_pr_session_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_pr_session_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_PR_SESSION_PREFIX F_LOSNING_PR_SESSION_PREFIX" "session_naming.pr_prefix" "${default_value}"
}

flow_resolve_issue_branch_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_issue_branch_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_ISSUE_BRANCH_PREFIX F_LOSNING_ISSUE_BRANCH_PREFIX" "session_naming.issue_branch_prefix" "${default_value}"
}

flow_resolve_pr_worktree_branch_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_pr_worktree_branch_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_PR_WORKTREE_BRANCH_PREFIX F_LOSNING_PR_WORKTREE_BRANCH_PREFIX" "session_naming.pr_worktree_branch_prefix" "${default_value}"
}

flow_resolve_managed_pr_branch_globs() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_managed_pr_branch_globs "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_MANAGED_PR_BRANCH_GLOBS F_LOSNING_MANAGED_PR_BRANCH_GLOBS" "session_naming.managed_pr_branch_globs" "${default_value}"
}

flow_escape_regex() {
  local raw_value="${1:-}"
  python3 - "${raw_value}" <<'PY'
import re
import sys

print(re.escape(sys.argv[1]))
PY
}

flow_managed_pr_prefixes() {
  local config_file="${1:-}"
  local managed_globs=""
  local branch_glob=""
  local prefix=""

  managed_globs="$(flow_resolve_managed_pr_branch_globs "${config_file}")"
  for branch_glob in ${managed_globs}; do
    prefix="${branch_glob%\*}"
    [[ -n "${prefix}" ]] || continue
    printf '%s\n' "${prefix}"
  done
}

flow_managed_pr_prefixes_json() {
  local config_file="${1:-}"
  local prefixes=()
  local prefix=""

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    prefixes+=("${prefix}")
  done < <(flow_managed_pr_prefixes "${config_file}")

  python3 - "${prefixes[@]}" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1:]))
PY
}

flow_managed_issue_branch_regex() {
  local config_file="${1:-}"
  local prefix=""
  local normalized_prefix=""
  local escaped_prefix=""
  local joined=""

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    normalized_prefix="${prefix%/}"
    escaped_prefix="$(flow_escape_regex "${normalized_prefix}")"
    if [[ -n "${joined}" ]]; then
      joined="${joined}|${escaped_prefix}"
    else
      joined="${escaped_prefix}"
    fi
  done < <(flow_managed_pr_prefixes "${config_file}")

  if [[ -z "${joined}" ]]; then
    joined="$(flow_escape_regex "agent/$(flow_resolve_adapter_id "${config_file}")")"
  fi

  printf '^(?:%s)/issue-(?<id>[0-9]+)(?:-|$)\n' "${joined}"
}

