flow_export_execution_env() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  [[ -f "${config_file}" ]] || return 0

  local repo_id=""
  local coding_worker=""
  local provider_quota_cooldowns=""
  local provider_pool_order=""
  local provider_pool_selection=""
  local explicit_coding_worker=""
  local active_provider_pool_name=""
  local active_provider_backend=""
  local active_provider_model=""
  local active_provider_key=""
  local active_provider_next_attempt_epoch=""
  local active_provider_next_attempt_at=""
  local active_provider_last_reason=""
  local active_provider_pools_exhausted="no"
  local active_provider_selection_reason="legacy-config"
  local safe_profile=""
  local bypass_profile=""
  local claude_model=""
  local claude_permission_mode=""
  local claude_effort=""
  local claude_timeout=""
  local claude_max_attempts=""
  local claude_retry_backoff_seconds=""
  local openclaw_model=""
  local openclaw_thinking=""
  local openclaw_timeout=""
  local openclaw_stall=""
  local ollama_model=""
  local ollama_base_url=""
  local ollama_timeout=""
  local pi_model=""
  local pi_thinking=""
  local pi_timeout=""
  local opencode_model=""
  local opencode_timeout=""
  local kilo_model=""
  local kilo_timeout=""

  repo_id="$(flow_resolve_repo_id "${config_file}")"
  provider_quota_cooldowns="$(flow_resolve_provider_quota_cooldowns "${config_file}")"
  provider_pool_order="$(flow_resolve_provider_pool_order "${config_file}")"
  explicit_coding_worker="${ACP_CODING_WORKER:-}"
  if [[ -z "${explicit_coding_worker}" && -n "${provider_pool_order}" ]]; then
    provider_pool_selection="$(flow_selected_provider_pool_env "${config_file}" || true)"
  fi

  if [[ -n "${provider_pool_selection}" ]]; then
    active_provider_pool_name="$(flow_kv_get "${provider_pool_selection}" "POOL_NAME")"
    active_provider_backend="$(flow_kv_get "${provider_pool_selection}" "BACKEND")"
    active_provider_model="$(flow_kv_get "${provider_pool_selection}" "MODEL")"
    active_provider_key="$(flow_kv_get "${provider_pool_selection}" "PROVIDER_KEY")"
    active_provider_next_attempt_epoch="$(flow_kv_get "${provider_pool_selection}" "NEXT_ATTEMPT_EPOCH")"
    active_provider_next_attempt_at="$(flow_kv_get "${provider_pool_selection}" "NEXT_ATTEMPT_AT")"
    active_provider_last_reason="$(flow_kv_get "${provider_pool_selection}" "LAST_REASON")"
    active_provider_pools_exhausted="$(flow_kv_get "${provider_pool_selection}" "POOLS_EXHAUSTED")"
    active_provider_selection_reason="$(flow_kv_get "${provider_pool_selection}" "SELECTION_REASON")"

    coding_worker="${active_provider_backend}"
    safe_profile="$(flow_kv_get "${provider_pool_selection}" "SAFE_PROFILE")"
    bypass_profile="$(flow_kv_get "${provider_pool_selection}" "BYPASS_PROFILE")"
    claude_model="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_MODEL")"
    claude_permission_mode="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_PERMISSION_MODE")"
    claude_effort="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_EFFORT")"
    claude_timeout="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_TIMEOUT_SECONDS")"
    claude_max_attempts="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_MAX_ATTEMPTS")"
    claude_retry_backoff_seconds="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_RETRY_BACKOFF_SECONDS")"
    openclaw_model="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_MODEL")"
    openclaw_thinking="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_THINKING")"
    openclaw_timeout="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_TIMEOUT_SECONDS")"
    openclaw_stall="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_STALL_SECONDS")"
    ollama_model="$(flow_kv_get "${provider_pool_selection}" "OLLAMA_MODEL")"
    ollama_base_url="$(flow_kv_get "${provider_pool_selection}" "OLLAMA_BASE_URL")"
    ollama_timeout="$(flow_kv_get "${provider_pool_selection}" "OLLAMA_TIMEOUT_SECONDS")"
    pi_model="$(flow_kv_get "${provider_pool_selection}" "PI_MODEL")"
    pi_thinking="$(flow_kv_get "${provider_pool_selection}" "PI_THINKING")"
    pi_timeout="$(flow_kv_get "${provider_pool_selection}" "PI_TIMEOUT_SECONDS")"
    opencode_model="$(flow_kv_get "${provider_pool_selection}" "OPENCODE_MODEL")"
    opencode_timeout="$(flow_kv_get "${provider_pool_selection}" "OPENCODE_TIMEOUT_SECONDS")"
    kilo_model="$(flow_kv_get "${provider_pool_selection}" "KILO_MODEL")"
    kilo_timeout="$(flow_kv_get "${provider_pool_selection}" "KILO_TIMEOUT_SECONDS")"
  else
    if [[ -n "${explicit_coding_worker}" ]]; then
      active_provider_selection_reason="env-override"
    fi
    coding_worker="$(flow_env_or_config "${config_file}" "ACP_CODING_WORKER" "execution.coding_worker" "")"
    safe_profile="$(flow_env_or_config "${config_file}" "ACP_CODEX_PROFILE_SAFE F_LOSNING_CODEX_PROFILE_SAFE" "execution.safe_profile" "")"
    bypass_profile="$(flow_env_or_config "${config_file}" "ACP_CODEX_PROFILE_BYPASS F_LOSNING_CODEX_PROFILE_BYPASS" "execution.bypass_profile" "")"
    claude_model="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_MODEL F_LOSNING_CLAUDE_MODEL" "execution.claude.model" "")"
    claude_permission_mode="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_PERMISSION_MODE F_LOSNING_CLAUDE_PERMISSION_MODE" "execution.claude.permission_mode" "")"
    claude_effort="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_EFFORT F_LOSNING_CLAUDE_EFFORT" "execution.claude.effort" "")"
    claude_timeout="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_TIMEOUT_SECONDS F_LOSNING_CLAUDE_TIMEOUT_SECONDS" "execution.claude.timeout_seconds" "")"
    claude_max_attempts="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_MAX_ATTEMPTS F_LOSNING_CLAUDE_MAX_ATTEMPTS" "execution.claude.max_attempts" "")"
    claude_retry_backoff_seconds="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_RETRY_BACKOFF_SECONDS F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS" "execution.claude.retry_backoff_seconds" "")"
    openclaw_model="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_MODEL F_LOSNING_OPENCLAW_MODEL" "execution.openclaw.model" "")"
    openclaw_thinking="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_THINKING F_LOSNING_OPENCLAW_THINKING" "execution.openclaw.thinking" "")"
    openclaw_timeout="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_TIMEOUT_SECONDS F_LOSNING_OPENCLAW_TIMEOUT_SECONDS" "execution.openclaw.timeout_seconds" "")"
    openclaw_stall="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_STALL_SECONDS F_LOSNING_OPENCLAW_STALL_SECONDS" "execution.openclaw.stall_seconds" "")"
    ollama_model="$(flow_env_or_config "${config_file}" "ACP_OLLAMA_MODEL F_LOSNING_OLLAMA_MODEL" "execution.ollama.model" "")"
    ollama_base_url="$(flow_env_or_config "${config_file}" "ACP_OLLAMA_BASE_URL F_LOSNING_OLLAMA_BASE_URL" "execution.ollama.base_url" "")"
    ollama_timeout="$(flow_env_or_config "${config_file}" "ACP_OLLAMA_TIMEOUT_SECONDS F_LOSNING_OLLAMA_TIMEOUT_SECONDS" "execution.ollama.timeout_seconds" "")"
    pi_model="$(flow_env_or_config "${config_file}" "ACP_PI_MODEL F_LOSNING_PI_MODEL" "execution.pi.model" "")"
    pi_thinking="$(flow_env_or_config "${config_file}" "ACP_PI_THINKING F_LOSNING_PI_THINKING" "execution.pi.thinking" "")"
    pi_timeout="$(flow_env_or_config "${config_file}" "ACP_PI_TIMEOUT_SECONDS F_LOSNING_PI_TIMEOUT_SECONDS" "execution.pi.timeout_seconds" "")"
    opencode_model="$(flow_env_or_config "${config_file}" "ACP_OPENCODE_MODEL F_LOSNING_OPENCODE_MODEL" "execution.opencode.model" "")"
    opencode_timeout="$(flow_env_or_config "${config_file}" "ACP_OPENCODE_TIMEOUT_SECONDS F_LOSNING_OPENCODE_TIMEOUT_SECONDS" "execution.opencode.timeout_seconds" "")"
    kilo_model="$(flow_env_or_config "${config_file}" "ACP_KILO_MODEL F_LOSNING_KILO_MODEL" "execution.kilo.model" "")"
    kilo_timeout="$(flow_env_or_config "${config_file}" "ACP_KILO_TIMEOUT_SECONDS F_LOSNING_KILO_TIMEOUT_SECONDS" "execution.kilo.timeout_seconds" "")"
  fi

  if [[ -n "${coding_worker}" ]]; then
    export ACP_CODING_WORKER="${coding_worker}"
  fi
  if [[ -n "${repo_id}" ]]; then
    export F_LOSNING_REPO_ID="${repo_id}"
    export ACP_REPO_ID="${repo_id}"
    export F_LOSNING_GITHUB_REPOSITORY_ID="${repo_id}"
    export ACP_GITHUB_REPOSITORY_ID="${repo_id}"
  fi
  if [[ -n "${provider_quota_cooldowns}" ]]; then
    export F_LOSNING_PROVIDER_QUOTA_COOLDOWNS="${provider_quota_cooldowns}"
    export ACP_PROVIDER_QUOTA_COOLDOWNS="${provider_quota_cooldowns}"
  fi
  export F_LOSNING_PROVIDER_POOL_ORDER="${provider_pool_order}"
  export ACP_PROVIDER_POOL_ORDER="${provider_pool_order}"
  export F_LOSNING_ACTIVE_PROVIDER_POOL_NAME="${active_provider_pool_name}"
  export ACP_ACTIVE_PROVIDER_POOL_NAME="${active_provider_pool_name}"
  export F_LOSNING_ACTIVE_PROVIDER_BACKEND="${active_provider_backend}"
  export ACP_ACTIVE_PROVIDER_BACKEND="${active_provider_backend}"
  export F_LOSNING_ACTIVE_PROVIDER_MODEL="${active_provider_model}"
  export ACP_ACTIVE_PROVIDER_MODEL="${active_provider_model}"
  export F_LOSNING_ACTIVE_PROVIDER_KEY="${active_provider_key}"
  export ACP_ACTIVE_PROVIDER_KEY="${active_provider_key}"
  export F_LOSNING_PROVIDER_POOLS_EXHAUSTED="${active_provider_pools_exhausted}"
  export ACP_PROVIDER_POOLS_EXHAUSTED="${active_provider_pools_exhausted}"
  export F_LOSNING_PROVIDER_POOL_SELECTION_REASON="${active_provider_selection_reason}"
  export ACP_PROVIDER_POOL_SELECTION_REASON="${active_provider_selection_reason}"
  export F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH="${active_provider_next_attempt_epoch}"
  export ACP_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH="${active_provider_next_attempt_epoch}"
  export F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_AT="${active_provider_next_attempt_at}"
  export ACP_PROVIDER_POOL_NEXT_ATTEMPT_AT="${active_provider_next_attempt_at}"
  export F_LOSNING_PROVIDER_POOL_LAST_REASON="${active_provider_last_reason}"
  export ACP_PROVIDER_POOL_LAST_REASON="${active_provider_last_reason}"
  if [[ -n "${safe_profile}" ]]; then
    export F_LOSNING_CODEX_PROFILE_SAFE="${safe_profile}"
    export ACP_CODEX_PROFILE_SAFE="${safe_profile}"
  fi
  if [[ -n "${bypass_profile}" ]]; then
    export F_LOSNING_CODEX_PROFILE_BYPASS="${bypass_profile}"
    export ACP_CODEX_PROFILE_BYPASS="${bypass_profile}"
  fi
  if [[ -n "${claude_model}" ]]; then
    export F_LOSNING_CLAUDE_MODEL="${claude_model}"
    export ACP_CLAUDE_MODEL="${claude_model}"
  fi
  if [[ -n "${claude_permission_mode}" ]]; then
    export F_LOSNING_CLAUDE_PERMISSION_MODE="${claude_permission_mode}"
    export ACP_CLAUDE_PERMISSION_MODE="${claude_permission_mode}"
  fi
  if [[ -n "${claude_effort}" ]]; then
    export F_LOSNING_CLAUDE_EFFORT="${claude_effort}"
    export ACP_CLAUDE_EFFORT="${claude_effort}"
  fi
  if [[ -n "${claude_timeout}" ]]; then
    export F_LOSNING_CLAUDE_TIMEOUT_SECONDS="${claude_timeout}"
    export ACP_CLAUDE_TIMEOUT_SECONDS="${claude_timeout}"
  fi
  if [[ -n "${claude_max_attempts}" ]]; then
    export F_LOSNING_CLAUDE_MAX_ATTEMPTS="${claude_max_attempts}"
    export ACP_CLAUDE_MAX_ATTEMPTS="${claude_max_attempts}"
  fi
  if [[ -n "${claude_retry_backoff_seconds}" ]]; then
    export F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS="${claude_retry_backoff_seconds}"
    export ACP_CLAUDE_RETRY_BACKOFF_SECONDS="${claude_retry_backoff_seconds}"
  fi
  if [[ -n "${openclaw_model}" ]]; then
    export F_LOSNING_OPENCLAW_MODEL="${openclaw_model}"
    export ACP_OPENCLAW_MODEL="${openclaw_model}"
  fi
  if [[ -n "${openclaw_thinking}" ]]; then
    export F_LOSNING_OPENCLAW_THINKING="${openclaw_thinking}"
    export ACP_OPENCLAW_THINKING="${openclaw_thinking}"
  fi
  if [[ -n "${openclaw_timeout}" ]]; then
    export F_LOSNING_OPENCLAW_TIMEOUT_SECONDS="${openclaw_timeout}"
    export ACP_OPENCLAW_TIMEOUT_SECONDS="${openclaw_timeout}"
  fi
  if [[ -n "${openclaw_stall}" ]]; then
    export F_LOSNING_OPENCLAW_STALL_SECONDS="${openclaw_stall}"
    export ACP_OPENCLAW_STALL_SECONDS="${openclaw_stall}"
  fi
  if [[ -n "${ollama_model}" ]]; then
    export F_LOSNING_OLLAMA_MODEL="${ollama_model}"
    export ACP_OLLAMA_MODEL="${ollama_model}"
  fi
  if [[ -n "${ollama_base_url}" ]]; then
    export F_LOSNING_OLLAMA_BASE_URL="${ollama_base_url}"
    export ACP_OLLAMA_BASE_URL="${ollama_base_url}"
  fi
  if [[ -n "${ollama_timeout}" ]]; then
    export F_LOSNING_OLLAMA_TIMEOUT_SECONDS="${ollama_timeout}"
    export ACP_OLLAMA_TIMEOUT_SECONDS="${ollama_timeout}"
  fi
  if [[ -n "${pi_model}" ]]; then
    export F_LOSNING_PI_MODEL="${pi_model}"
    export ACP_PI_MODEL="${pi_model}"
  fi
  if [[ -n "${pi_thinking}" ]]; then
    export F_LOSNING_PI_THINKING="${pi_thinking}"
    export ACP_PI_THINKING="${pi_thinking}"
  fi
  if [[ -n "${pi_timeout}" ]]; then
    export F_LOSNING_PI_TIMEOUT_SECONDS="${pi_timeout}"
    export ACP_PI_TIMEOUT_SECONDS="${pi_timeout}"
  fi
  if [[ -n "${opencode_model}" ]]; then
    export F_LOSNING_OPENCODE_MODEL="${opencode_model}"
    export ACP_OPENCODE_MODEL="${opencode_model}"
  fi
  if [[ -n "${opencode_timeout}" ]]; then
    export F_LOSNING_OPENCODE_TIMEOUT_SECONDS="${opencode_timeout}"
    export ACP_OPENCODE_TIMEOUT_SECONDS="${opencode_timeout}"
  fi
  if [[ -n "${kilo_model}" ]]; then
    export F_LOSNING_KILO_MODEL="${kilo_model}"
    export ACP_KILO_MODEL="${kilo_model}"
  fi
  if [[ -n "${kilo_timeout}" ]]; then
    export F_LOSNING_KILO_TIMEOUT_SECONDS="${kilo_timeout}"
    export ACP_KILO_TIMEOUT_SECONDS="${kilo_timeout}"
  fi

  flow_export_github_cli_auth_env "$(flow_resolve_repo_slug "${config_file}")"
  flow_export_project_env_aliases
}
