flow_github_pr_merge() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"
  local merge_method="${3:-squash}"
  local delete_branch="${4:-no}"
  local pr_json=""
  local head_ref=""
  local encoded_ref=""

  if flow_using_gitea; then
    printf '%s' "$(
      MERGE_METHOD="${merge_method}" DELETE_BRANCH="${delete_branch}" python3 - <<'PY'
import json
import os

method = os.environ.get("MERGE_METHOD", "squash")
delete_branch = os.environ.get("DELETE_BRANCH", "no") == "yes"
method_map = {"merge": "merge", "squash": "squash", "rebase": "rebase"}
print(json.dumps({
    "Do": method_map.get(method, "squash"),
    "delete_branch_after_merge": delete_branch,
}))
PY
    )" | flow_github_api_repo "${repo_slug}" "pulls/${pr_number}/merge" --method POST --input - >/dev/null
    return $?
  fi

  if gh pr merge "${pr_number}" -R "${repo_slug}" "--${merge_method}" $([[ "${delete_branch}" == "yes" ]] && printf '%s' '--delete-branch') --admin >/dev/null 2>&1; then
    return 0
  fi

  printf '{"merge_method":"%s"}' "${merge_method}" \
    | flow_github_api_repo "${repo_slug}" "pulls/${pr_number}/merge" --method PUT --input - >/dev/null

  if [[ "${delete_branch}" == "yes" ]]; then
    pr_json="$(flow_github_pr_view_json "${repo_slug}" "${pr_number}" 2>/dev/null || printf '{}\n')"
    head_ref="$(jq -r '.headRefName // ""' <<<"${pr_json}")"
    if [[ -n "${head_ref}" ]]; then
      encoded_ref="$(flow_github_urlencode "heads/${head_ref}")"
      flow_github_api_repo "${repo_slug}" "git/refs/${encoded_ref}" --method DELETE >/dev/null 2>&1 || true
    fi
  fi
}

flow_config_get() {
  local config_file="${1:?config file required}"
  local target_path="${2:?target path required}"

  python3 - "$config_file" "$target_path" <<'PY'
import sys

config_file = sys.argv[1]
target_path = sys.argv[2]

stack = []
found = False

with open(config_file, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue
        if ":" not in raw_line:
            continue

        indent = len(raw_line) - len(raw_line.lstrip())
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("\"'")

        while stack and indent <= stack[-1][0]:
            stack.pop()

        stack.append((indent, key))
        current_path = ".".join(part for _, part in stack)

        if current_path == target_path and value:
            print(value)
            found = True
            break

if not found:
    print("")
PY
}

flow_kv_get() {
  local payload="${1:-}"
  local key="${2:?key required}"

  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' <<<"${payload}"
}

flow_env_or_config() {
  local config_file="${1:?config file required}"
  local env_names="${2:?env names required}"
  local config_key="${3:?config key required}"
  local default_value="${4:-}"
  local env_name=""
  local value=""

  for env_name in ${env_names}; do
    value="${!env_name:-}"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done

  if [[ -f "${config_file}" ]]; then
    value="$(flow_config_get "${config_file}" "${config_key}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  printf '%s\n' "${default_value}"
}

flow_resolve_adapter_id() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_profile_id)"
  flow_env_or_config "${config_file}" "ACP_PROJECT_ID AGENT_PROJECT_ID" "id" "${default_value}"
}

flow_resolve_profile_notes_file() {
  local config_file="${1:-}"
  local config_dir=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  config_dir="$(cd "$(dirname "${config_file}")" 2>/dev/null && pwd -P || dirname "${config_file}")"
  printf '%s/README.md
' "${config_dir}"
}

flow_default_issue_session_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf '%s-issue-\n' "${adapter_id}"
}

flow_default_pr_session_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf '%s-pr-\n' "${adapter_id}"
}

flow_default_issue_branch_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'agent/%s/issue\n' "${adapter_id}"
}

flow_default_pr_worktree_branch_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'agent/%s/pr\n' "${adapter_id}"
}

flow_default_managed_pr_branch_globs() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'agent/%s/* codex/* openclaw/*\n' "${adapter_id}"
}

flow_default_agent_root() {
  local config_file="${1:-}"
  local adapter_id=""
  local platform_home="${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf '%s/projects/%s
' "${platform_home}" "${adapter_id}"
}

flow_default_repo_slug() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'example/%s
' "${adapter_id}"
}

flow_default_repo_id() {
  printf '\n'
}

flow_default_repo_root() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/repo
' "${agent_root}"
}

flow_default_worktree_root() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/worktrees
' "${agent_root}"
}

flow_default_retained_repo_root() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/retained
' "${agent_root}"
}

flow_default_vscode_workspace_file() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/workspace.code-workspace
' "${agent_root}"
}
flow_resolve_repo_slug() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_repo_slug "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_REPO_SLUG F_LOSNING_REPO_SLUG" "repo.slug" "${default_value}"
}

flow_resolve_repo_id() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_repo_id)"
  flow_env_or_config "${config_file}" "ACP_REPO_ID F_LOSNING_REPO_ID ACP_GITHUB_REPOSITORY_ID F_LOSNING_GITHUB_REPOSITORY_ID" "repo.id" "${default_value}"
}

flow_resolve_default_branch() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_DEFAULT_BRANCH F_LOSNING_DEFAULT_BRANCH" "repo.default_branch" "main"
}

flow_resolve_project_label() {
  local config_file="${1:-}"
  local repo_slug=""
  local adapter_id=""
  local label=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  repo_slug="$(flow_resolve_repo_slug "${config_file}")"
  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  label="${repo_slug##*/}"
  if [[ -n "${label}" ]]; then
    printf '%s\n' "${label}"
  else
    printf '%s\n' "${adapter_id}"
  fi
}

flow_resolve_repo_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_REPO_ROOT F_LOSNING_REPO_ROOT" "repo.root" "${default_value}"
}

flow_resolve_agent_root() {
  local config_file="${1:-}"
  local default_value=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  default_value="$(flow_default_agent_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_AGENT_ROOT F_LOSNING_AGENT_ROOT" "runtime.orchestrator_agent_root" "${default_value}"
}

flow_resolve_agent_repo_root() {
  local config_file="${1:-}"
  local default_value=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  default_value="$(flow_resolve_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_AGENT_REPO_ROOT F_LOSNING_AGENT_REPO_ROOT" "runtime.agent_repo_root" "${default_value}"
}

flow_resolve_worktree_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_worktree_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_WORKTREE_ROOT F_LOSNING_WORKTREE_ROOT" "runtime.worktree_root" "${default_value}"
}

flow_resolve_runs_root() {
  local config_file="${1:-}"
  local default_value=""
  local explicit_root="${ACP_RUNS_ROOT:-${F_LOSNING_RUNS_ROOT:-}}"
  local umbrella_root="${ACP_AGENT_ROOT:-${F_LOSNING_AGENT_ROOT:-}}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ -n "${explicit_root}" ]]; then
    printf '%s\n' "${explicit_root}"
    return 0
  fi

  default_value="$(flow_resolve_agent_root "${config_file}")/runs"
  if [[ -n "${umbrella_root}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  flow_env_or_config "${config_file}" "ACP_RUNS_ROOT F_LOSNING_RUNS_ROOT" "runtime.runs_root" "${default_value}"
}

flow_resolve_state_root() {
  local config_file="${1:-}"
  local default_value=""
  local explicit_root="${ACP_STATE_ROOT:-${F_LOSNING_STATE_ROOT:-}}"
  local umbrella_root="${ACP_AGENT_ROOT:-${F_LOSNING_AGENT_ROOT:-}}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ -n "${explicit_root}" ]]; then
    printf '%s\n' "${explicit_root}"
    return 0
  fi

  default_value="$(flow_resolve_agent_root "${config_file}")/state"
  if [[ -n "${umbrella_root}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  flow_env_or_config "${config_file}" "ACP_STATE_ROOT F_LOSNING_STATE_ROOT" "runtime.state_root" "${default_value}"
}

flow_resolve_history_root() {
  local config_file="${1:-}"
  local default_value=""
  local explicit_root="${ACP_HISTORY_ROOT:-${F_LOSNING_HISTORY_ROOT:-}}"
  local umbrella_root="${ACP_AGENT_ROOT:-${F_LOSNING_AGENT_ROOT:-}}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ -n "${explicit_root}" ]]; then
    printf '%s\n' "${explicit_root}"
    return 0
  fi

  default_value="$(flow_resolve_agent_root "${config_file}")/history"
  if [[ -n "${umbrella_root}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  flow_env_or_config "${config_file}" "ACP_HISTORY_ROOT F_LOSNING_HISTORY_ROOT" "runtime.history_root" "${default_value}"
}

flow_resolve_retained_repo_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_retained_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_RETAINED_REPO_ROOT F_LOSNING_RETAINED_REPO_ROOT" "runtime.retained_repo_root" "${default_value}"
}

flow_resolve_source_repo_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_resolve_retained_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_SOURCE_REPO_ROOT F_LOSNING_SOURCE_REPO_ROOT" "runtime.source_repo_root" "${default_value}"
}

flow_resolve_vscode_workspace_file() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_vscode_workspace_file "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_VSCODE_WORKSPACE_FILE F_LOSNING_VSCODE_WORKSPACE_FILE" "runtime.vscode_workspace_file" "${default_value}"
}

flow_resolve_web_playwright_command() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_WEB_PLAYWRIGHT_COMMAND F_LOSNING_WEB_PLAYWRIGHT_COMMAND" "execution.verification.web_playwright_command" "pnpm exec playwright test"
}

flow_resolve_codex_quota_bin() {
  local flow_root="${1:-}"
  local shared_home=""
  local explicit_bin="${ACP_CODEX_QUOTA_BIN:-${F_LOSNING_CODEX_QUOTA_BIN:-}}"
  local candidate=""

  if [[ -n "${explicit_bin}" ]]; then
    printf '%s\n' "${explicit_bin}"
    return 0
  fi

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  shared_home="${SHARED_AGENT_HOME:-$(resolve_shared_agent_home "${flow_root}")}"

  for candidate in \
    "${flow_root}/tools/bin/codex-quota" \
    "${shared_home}/tools/bin/codex-quota"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(command -v codex-quota 2>/dev/null || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s\n' "${flow_root}/tools/bin/codex-quota"
}

flow_resolve_codex_quota_manager_script() {
  local flow_root="${1:-}"
  local shared_home=""
  local explicit_script="${ACP_CODEX_QUOTA_MANAGER_SCRIPT:-${F_LOSNING_CODEX_QUOTA_MANAGER_SCRIPT:-}}"
  local candidate=""

  if [[ -n "${explicit_script}" ]]; then
    printf '%s\n' "${explicit_script}"
    return 0
  fi

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  shared_home="${SHARED_AGENT_HOME:-$(resolve_shared_agent_home "${flow_root}")}"

  for candidate in \
    "${flow_root}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" \
    "${shared_home}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" \
    "${shared_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf '%s\n' "${flow_root}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"
}

flow_resolve_template_file() {
  local template_name="${1:?template name required}"
  local workspace_dir="${2:-}"
  local config_file="${3:-}"
  local flow_root=""
  local profile_id=""
  local config_dir=""
  local template_dir=""
  local candidate=""
  local workspace_real=""
  local canonical_tools_real=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
  config_dir="$(cd "$(dirname "${config_file}")" 2>/dev/null && pwd -P || dirname "${config_file}")"

  for template_dir in \
    "${AGENT_CONTROL_PLANE_TEMPLATE_DIR:-}" \
    "${ACP_TEMPLATE_DIR:-}" \
    "${F_LOSNING_TEMPLATE_DIR:-}"; do
    if [[ -n "${template_dir}" && -f "${template_dir}/${template_name}" ]]; then
      printf '%s\n' "${template_dir}/${template_name}"
      return 0
    fi
  done

  if [[ -n "${workspace_dir}" && -f "${workspace_dir}/templates/${template_name}" ]]; then
    workspace_real="$(cd "${workspace_dir}" && pwd -P)"
    canonical_tools_real="$(cd "${flow_root}/tools" && pwd -P)"
    if [[ "${workspace_real}" != "${canonical_tools_real}" ]]; then
      printf '%s\n' "${workspace_dir}/templates/${template_name}"
      return 0
    fi
  fi

  candidate="${config_dir}/templates/${template_name}"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  if [[ -n "${workspace_dir}" && -f "${workspace_dir}/templates/${template_name}" ]]; then
    printf '%s\n' "${workspace_dir}/templates/${template_name}"
    return 0
  fi

  printf '%s\n' "${flow_root}/tools/templates/${template_name}"
}

flow_resolve_retry_cooldowns() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_RETRY_COOLDOWNS F_LOSNING_RETRY_COOLDOWNS" "execution.retry.cooldowns" "300,900,1800,3600"
}

flow_resolve_provider_quota_cooldowns() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_PROVIDER_QUOTA_COOLDOWNS F_LOSNING_PROVIDER_QUOTA_COOLDOWNS" "execution.provider_quota.cooldowns" "300,900,1800,3600"
}

flow_resolve_provider_pool_order() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_PROVIDER_POOL_ORDER F_LOSNING_PROVIDER_POOL_ORDER" "execution.provider_pool_order" ""
}

flow_provider_pool_names() {
  local config_file="${1:-}"
  local order=""
  local pool_name=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  order="$(flow_resolve_provider_pool_order "${config_file}")"
  for pool_name in ${order}; do
    [[ -n "${pool_name}" ]] || continue
    printf '%s\n' "${pool_name}"
  done
}

flow_provider_pools_enabled() {
  local config_file="${1:-}"
  [[ -n "$(flow_resolve_provider_pool_order "${config_file}")" ]]
}

flow_provider_pool_value() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"
  local relative_path="${3:?relative path required}"

  flow_config_get "${config_file}" "execution.provider_pools.${pool_name}.${relative_path}"
}

flow_provider_pool_backend() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "coding_worker"
}

flow_provider_pool_safe_profile() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "safe_profile"
}

flow_provider_pool_bypass_profile() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "bypass_profile"
}

flow_provider_pool_claude_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.model"
}

flow_provider_pool_claude_permission_mode() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.permission_mode"
}

flow_provider_pool_claude_effort() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.effort"
}

flow_provider_pool_claude_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.timeout_seconds"
}

flow_provider_pool_claude_max_attempts() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.max_attempts"
}

flow_provider_pool_claude_retry_backoff_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.retry_backoff_seconds"
}

flow_provider_pool_openclaw_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "openclaw.model"
}

flow_provider_pool_openclaw_thinking() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "openclaw.thinking"
}

flow_provider_pool_openclaw_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "openclaw.timeout_seconds"
}

flow_provider_pool_ollama_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "ollama.model"
}

flow_provider_pool_ollama_base_url() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "ollama.base_url"
}

flow_provider_pool_ollama_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "ollama.timeout_seconds"
}

flow_provider_pool_pi_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "pi.model"
}

flow_provider_pool_pi_thinking() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "pi.thinking"
}

flow_provider_pool_pi_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "pi.timeout_seconds"
}

flow_provider_pool_opencode_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "opencode.model"
}

flow_provider_pool_opencode_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "opencode.timeout_seconds"
}

flow_provider_pool_kilo_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "kilo.model"
}

flow_provider_pool_kilo_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "kilo.timeout_seconds"
}

flow_sanitize_provider_key() {
  local raw_key="${1:?raw key required}"

  printf '%s' "${raw_key}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

flow_provider_pool_model_identity() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"
  local backend=""

  backend="$(flow_provider_pool_backend "${config_file}" "${pool_name}")"
  case "${backend}" in
    codex)
      flow_provider_pool_safe_profile "${config_file}" "${pool_name}"
      ;;
    claude)
      flow_provider_pool_claude_model "${config_file}" "${pool_name}"
      ;;
    openclaw)
      flow_provider_pool_openclaw_model "${config_file}" "${pool_name}"
      ;;
    ollama)
      flow_provider_pool_ollama_model "${config_file}" "${pool_name}"
      ;;
    pi)
      flow_provider_pool_pi_model "${config_file}" "${pool_name}"
      ;;
    opencode)
      flow_provider_pool_opencode_model "${config_file}" "${pool_name}"
      ;;
    kilo)
      flow_provider_pool_kilo_model "${config_file}" "${pool_name}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

