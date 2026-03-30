#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  profile-smoke.sh [--profile-id <id>] [--help]

Validate available control-plane profiles before using them in the scheduler.
Checks:
  - canonical profile YAML exists
  - render-flow-config resolves the selected profile
  - required runtime/session fields are non-empty
  - session and branch prefixes do not collide across installed profiles
EOF
}

profile_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_filter="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

flow_skill_dir="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
render_script="${flow_skill_dir}/tools/bin/render-flow-config.sh"
profiles_file="$(mktemp)"
records_file="$(mktemp)"
trap 'rm -f "$profiles_file" "$records_file"' EXIT
failures=0

if [[ -n "$profile_filter" ]]; then
  printf '%s\n' "$profile_filter" >"$profiles_file"
else
  flow_list_profile_ids "${flow_skill_dir}" >"$profiles_file"
fi

if [[ ! -s "$profiles_file" ]]; then
  echo "no installed profiles found" >&2
  exit 1
fi

render_field() {
  local key="${1:?key required}"
  local payload="${2:-}"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' <<<"$payload"
}

report_failure() {
  local profile_id="${1:?profile id required}"
  local message="${2:?message required}"
  printf 'PROFILE_ID=%s\n' "$profile_id"
  printf 'PROFILE_STATUS=failed\n'
  printf 'FAILURE=%s\n' "$message"
  failures=$((failures + 1))
}

require_nonempty() {
  local profile_id="${1:?profile id required}"
  local label="${2:?label required}"
  local value="${3:-}"
  if [[ -z "$value" ]]; then
    report_failure "$profile_id" "${label} missing"
    return 1
  fi
  return 0
}

require_positive_integer() {
  local profile_id="${1:?profile id required}"
  local label="${2:?label required}"
  local value="${3:-}"
  if [[ -z "$value" ]]; then
    report_failure "$profile_id" "${label} missing"
    return 1
  fi
  case "$value" in
    ''|*[!0-9]*|0)
      report_failure "$profile_id" "${label} must be a positive integer"
      return 1
      ;;
  esac
  return 0
}

require_nonnegative_integer() {
  local profile_id="${1:?profile id required}"
  local label="${2:?label required}"
  local value="${3:-}"
  if [[ -z "$value" ]]; then
    report_failure "$profile_id" "${label} missing"
    return 1
  fi
  case "$value" in
    ''|*[!0-9]*)
      report_failure "$profile_id" "${label} must be a non-negative integer"
      return 1
      ;;
  esac
  return 0
}

validate_provider_pool_config() {
  local profile_id="${1:?profile id required}"
  local config_yaml="${2:?config yaml required}"
  local pool_name="${3:?pool name required}"
  local pool_state=""
  local pool_valid=""
  local pool_backend=""
  local pool_model=""
  local pool_safe_profile=""
  local pool_bypass_profile=""
  local pool_claude_model=""
  local pool_claude_permission_mode=""
  local pool_claude_effort=""
  local pool_claude_timeout_seconds=""
  local pool_claude_max_attempts=""
  local pool_claude_retry_backoff_seconds=""
  local pool_openclaw_model=""
  local pool_openclaw_thinking=""
  local pool_openclaw_timeout_seconds=""
  local pool_failed="no"

  pool_state="$(flow_provider_pool_state_get "$config_yaml" "$pool_name")"
  pool_valid="$(flow_kv_get "$pool_state" "VALID")"
  pool_backend="$(flow_kv_get "$pool_state" "BACKEND")"
  pool_model="$(flow_kv_get "$pool_state" "MODEL")"
  pool_safe_profile="$(flow_kv_get "$pool_state" "SAFE_PROFILE")"
  pool_bypass_profile="$(flow_kv_get "$pool_state" "BYPASS_PROFILE")"
  pool_claude_model="$(flow_kv_get "$pool_state" "CLAUDE_MODEL")"
  pool_claude_permission_mode="$(flow_kv_get "$pool_state" "CLAUDE_PERMISSION_MODE")"
  pool_claude_effort="$(flow_kv_get "$pool_state" "CLAUDE_EFFORT")"
  pool_claude_timeout_seconds="$(flow_kv_get "$pool_state" "CLAUDE_TIMEOUT_SECONDS")"
  pool_claude_max_attempts="$(flow_kv_get "$pool_state" "CLAUDE_MAX_ATTEMPTS")"
  pool_claude_retry_backoff_seconds="$(flow_kv_get "$pool_state" "CLAUDE_RETRY_BACKOFF_SECONDS")"
  pool_openclaw_model="$(flow_kv_get "$pool_state" "OPENCLAW_MODEL")"
  pool_openclaw_thinking="$(flow_kv_get "$pool_state" "OPENCLAW_THINKING")"
  pool_openclaw_timeout_seconds="$(flow_kv_get "$pool_state" "OPENCLAW_TIMEOUT_SECONDS")"

  if [[ "${pool_valid}" != "yes" ]]; then
    report_failure "$profile_id" "provider pool ${pool_name} is invalid"
    pool_failed="yes"
  fi

  if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.coding_worker" "$pool_backend"; then
    pool_failed="yes"
  fi
  if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.model" "$pool_model"; then
    pool_failed="yes"
  fi

  case "$pool_backend" in
    codex)
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.safe_profile" "$pool_safe_profile"; then
        pool_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.bypass_profile" "$pool_bypass_profile"; then
        pool_failed="yes"
      fi
      ;;
    claude)
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.claude.model" "$pool_claude_model"; then
        pool_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.claude.permission_mode" "$pool_claude_permission_mode"; then
        pool_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.claude.effort" "$pool_claude_effort"; then
        pool_failed="yes"
      fi
      case "$pool_claude_effort" in
        low|medium|high|max) ;;
        *)
          report_failure "$profile_id" "provider_pool.${pool_name}.claude.effort must be one of: low, medium, high, max"
          pool_failed="yes"
          ;;
      esac
      if ! require_positive_integer "$profile_id" "provider_pool.${pool_name}.claude.timeout_seconds" "$pool_claude_timeout_seconds"; then
        pool_failed="yes"
      fi
      if ! require_positive_integer "$profile_id" "provider_pool.${pool_name}.claude.max_attempts" "$pool_claude_max_attempts"; then
        pool_failed="yes"
      fi
      if ! require_nonnegative_integer "$profile_id" "provider_pool.${pool_name}.claude.retry_backoff_seconds" "$pool_claude_retry_backoff_seconds"; then
        pool_failed="yes"
      fi
      ;;
    openclaw)
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.openclaw.model" "$pool_openclaw_model"; then
        pool_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "provider_pool.${pool_name}.openclaw.thinking" "$pool_openclaw_thinking"; then
        pool_failed="yes"
      fi
      if ! require_positive_integer "$profile_id" "provider_pool.${pool_name}.openclaw.timeout_seconds" "$pool_openclaw_timeout_seconds"; then
        pool_failed="yes"
      fi
      ;;
    '')
      ;;
    *)
      report_failure "$profile_id" "provider_pool.${pool_name}.coding_worker unsupported: ${pool_backend}"
      pool_failed="yes"
      ;;
  esac

  [[ "$pool_failed" != "yes" ]]
}

while IFS= read -r profile_id; do
  [[ -n "$profile_id" ]] || continue

  config_yaml="$(flow_find_profile_dir_by_id "${flow_skill_dir}" "${profile_id}")/control-plane.yaml"
  if [[ ! -f "$config_yaml" ]]; then
    report_failure "$profile_id" "canonical profile missing: $config_yaml"
    continue
  fi

  if ! render_output="$(ACP_PROJECT_ID="$profile_id" bash "$render_script" 2>/dev/null)"; then
    report_failure "$profile_id" "render-flow-config failed"
    continue
  fi

  rendered_profile_id="$(render_field "PROFILE_ID" "$render_output")"
  available_profiles="$(render_field "AVAILABLE_PROFILES" "$render_output")"
  effective_repo_root="$(render_field "EFFECTIVE_REPO_ROOT" "$render_output")"
  effective_agent_repo_root="$(render_field "EFFECTIVE_AGENT_REPO_ROOT" "$render_output")"
  effective_worktree_root="$(render_field "EFFECTIVE_WORKTREE_ROOT" "$render_output")"
  effective_runs_root="$(render_field "EFFECTIVE_RUNS_ROOT" "$render_output")"
  effective_state_root="$(render_field "EFFECTIVE_STATE_ROOT" "$render_output")"
  effective_coding_worker="$(render_field "EFFECTIVE_CODING_WORKER" "$render_output")"
  effective_codex_profile_safe="$(render_field "EFFECTIVE_CODEX_PROFILE_SAFE" "$render_output")"
  effective_codex_profile_bypass="$(render_field "EFFECTIVE_CODEX_PROFILE_BYPASS" "$render_output")"
  effective_provider_pool_order="$(render_field "EFFECTIVE_PROVIDER_POOL_ORDER" "$render_output")"
  effective_provider_pool_name="$(render_field "EFFECTIVE_PROVIDER_POOL_NAME" "$render_output")"
  effective_provider_pool_backend="$(render_field "EFFECTIVE_PROVIDER_POOL_BACKEND" "$render_output")"
  effective_provider_pool_model="$(render_field "EFFECTIVE_PROVIDER_POOL_MODEL" "$render_output")"
  effective_provider_pool_selection_reason="$(render_field "EFFECTIVE_PROVIDER_POOL_SELECTION_REASON" "$render_output")"
  effective_claude_model="$(render_field "EFFECTIVE_CLAUDE_MODEL" "$render_output")"
  effective_claude_permission_mode="$(render_field "EFFECTIVE_CLAUDE_PERMISSION_MODE" "$render_output")"
  effective_claude_effort="$(render_field "EFFECTIVE_CLAUDE_EFFORT" "$render_output")"
  effective_claude_timeout_seconds="$(render_field "EFFECTIVE_CLAUDE_TIMEOUT_SECONDS" "$render_output")"
  effective_claude_max_attempts="$(render_field "EFFECTIVE_CLAUDE_MAX_ATTEMPTS" "$render_output")"
  effective_claude_retry_backoff_seconds="$(render_field "EFFECTIVE_CLAUDE_RETRY_BACKOFF_SECONDS" "$render_output")"
  effective_openclaw_model="$(render_field "EFFECTIVE_OPENCLAW_MODEL" "$render_output")"
  effective_openclaw_thinking="$(render_field "EFFECTIVE_OPENCLAW_THINKING" "$render_output")"
  effective_openclaw_timeout_seconds="$(render_field "EFFECTIVE_OPENCLAW_TIMEOUT_SECONDS" "$render_output")"

  issue_prefix="$(flow_config_get "$config_yaml" "session_naming.issue_prefix")"
  pr_prefix="$(flow_config_get "$config_yaml" "session_naming.pr_prefix")"
  issue_branch_prefix="$(flow_config_get "$config_yaml" "session_naming.issue_branch_prefix")"
  pr_worktree_branch_prefix="$(flow_config_get "$config_yaml" "session_naming.pr_worktree_branch_prefix")"
  repo_slug="$(flow_config_get "$config_yaml" "repo.slug")"
  remote_repo_slug="$(flow_git_remote_repo_slug "$effective_repo_root" "origin" 2>/dev/null || true)"

  profile_failed="no"
  if [[ "$rendered_profile_id" != "$profile_id" ]]; then
    report_failure "$profile_id" "rendered profile id mismatch: ${rendered_profile_id:-<empty>}"
    profile_failed="yes"
  fi
  if [[ ",${available_profiles}," != *",${profile_id},"* ]]; then
    report_failure "$profile_id" "available profiles missing selected profile"
    profile_failed="yes"
  fi

  for required_pair in \
    "repo.slug:${repo_slug}" \
    "session_naming.issue_prefix:${issue_prefix}" \
    "session_naming.pr_prefix:${pr_prefix}" \
    "session_naming.issue_branch_prefix:${issue_branch_prefix}" \
    "session_naming.pr_worktree_branch_prefix:${pr_worktree_branch_prefix}" \
    "effective.repo_root:${effective_repo_root}" \
    "effective.agent_repo_root:${effective_agent_repo_root}" \
    "effective.worktree_root:${effective_worktree_root}" \
    "effective.runs_root:${effective_runs_root}" \
    "effective.state_root:${effective_state_root}" \
    "effective.coding_worker:${effective_coding_worker}"; do
    label="${required_pair%%:*}"
    value="${required_pair#*:}"
    if ! require_nonempty "$profile_id" "$label" "$value"; then
      profile_failed="yes"
    fi
  done

  case "$effective_coding_worker" in
    codex|openclaw|claude) ;;
    *)
      report_failure "$profile_id" "unsupported coding worker: ${effective_coding_worker}"
      profile_failed="yes"
      ;;
  esac

  case "$effective_coding_worker" in
    codex)
      if ! require_nonempty "$profile_id" "effective.codex_profile_safe" "$effective_codex_profile_safe"; then
        profile_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "effective.codex_profile_bypass" "$effective_codex_profile_bypass"; then
        profile_failed="yes"
      fi
      ;;
    claude)
      if ! require_nonempty "$profile_id" "effective.claude.model" "$effective_claude_model"; then
        profile_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "effective.claude.permission_mode" "$effective_claude_permission_mode"; then
        profile_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "effective.claude.effort" "$effective_claude_effort"; then
        profile_failed="yes"
      fi
      case "$effective_claude_effort" in
        low|medium|high|max) ;;
        *)
          report_failure "$profile_id" "effective.claude.effort must be one of: low, medium, high, max"
          profile_failed="yes"
          ;;
      esac
      if ! require_positive_integer "$profile_id" "effective.claude.timeout_seconds" "$effective_claude_timeout_seconds"; then
        profile_failed="yes"
      fi
      if ! require_positive_integer "$profile_id" "effective.claude.max_attempts" "$effective_claude_max_attempts"; then
        profile_failed="yes"
      fi
      if ! require_nonnegative_integer "$profile_id" "effective.claude.retry_backoff_seconds" "$effective_claude_retry_backoff_seconds"; then
        profile_failed="yes"
      fi
      ;;
    openclaw)
      if ! require_nonempty "$profile_id" "effective.openclaw.model" "$effective_openclaw_model"; then
        profile_failed="yes"
      fi
      if ! require_nonempty "$profile_id" "effective.openclaw.thinking" "$effective_openclaw_thinking"; then
        profile_failed="yes"
      fi
      if ! require_positive_integer "$profile_id" "effective.openclaw.timeout_seconds" "$effective_openclaw_timeout_seconds"; then
        profile_failed="yes"
      fi
      ;;
  esac

  if [[ -n "$effective_provider_pool_order" ]]; then
    if ! require_nonempty "$profile_id" "effective.provider_pool_name" "$effective_provider_pool_name"; then
      profile_failed="yes"
    fi
    if ! require_nonempty "$profile_id" "effective.provider_pool_backend" "$effective_provider_pool_backend"; then
      profile_failed="yes"
    fi
    if ! require_nonempty "$profile_id" "effective.provider_pool_model" "$effective_provider_pool_model"; then
      profile_failed="yes"
    fi
    if ! require_nonempty "$profile_id" "effective.provider_pool_selection_reason" "$effective_provider_pool_selection_reason"; then
      profile_failed="yes"
    fi
    if [[ -n "$effective_provider_pool_backend" && "$effective_provider_pool_backend" != "$effective_coding_worker" ]]; then
      report_failure "$profile_id" "effective provider pool backend does not match effective coding worker"
      profile_failed="yes"
    fi

    while IFS= read -r pool_name; do
      [[ -n "$pool_name" ]] || continue
      if ! validate_provider_pool_config "$profile_id" "$config_yaml" "$pool_name"; then
        profile_failed="yes"
      fi
    done < <(flow_provider_pool_names "$config_yaml")
  fi

  if [[ "$issue_prefix" == "$pr_prefix" ]]; then
    report_failure "$profile_id" "issue and pr session prefixes must differ"
    profile_failed="yes"
  fi

  if [[ "$issue_branch_prefix" == "$pr_worktree_branch_prefix" ]]; then
    report_failure "$profile_id" "issue and pr branch prefixes must differ"
    profile_failed="yes"
  fi

  if [[ -n "$remote_repo_slug" && "$remote_repo_slug" != "$repo_slug" ]]; then
    report_failure "$profile_id" "repo.slug mismatch: config=${repo_slug} origin=${remote_repo_slug}"
    profile_failed="yes"
  fi

  if [[ "$profile_failed" == "yes" ]]; then
    continue
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$profile_id" \
    "$issue_prefix" \
    "$pr_prefix" \
    "$issue_branch_prefix" \
    "$pr_worktree_branch_prefix" >>"$records_file"

  printf 'PROFILE_ID=%s\n' "$profile_id"
  printf 'CONFIG_YAML=%s\n' "$config_yaml"
  printf 'REPO_SLUG=%s\n' "$repo_slug"
  printf 'ISSUE_PREFIX=%s\n' "$issue_prefix"
  printf 'PR_PREFIX=%s\n' "$pr_prefix"
  printf 'ISSUE_BRANCH_PREFIX=%s\n' "$issue_branch_prefix"
  printf 'PR_WORKTREE_BRANCH_PREFIX=%s\n' "$pr_worktree_branch_prefix"
  printf 'CODING_WORKER=%s\n' "$effective_coding_worker"
  printf 'PROFILE_STATUS=ok\n'
done <"$profiles_file"

check_duplicate_column() {
  local column_index="${1:?column index required}"
  local label="${2:?label required}"
  local duplicate_output=""

  duplicate_output="$(
    awk -F'\t' -v column_index="$column_index" '
      {
        key = $column_index
        if (key == "") next
        counts[key] += 1
        if (profiles[key] == "") {
          profiles[key] = $1
        } else {
          profiles[key] = profiles[key] "," $1
        }
      }
      END {
        for (key in counts) {
          if (counts[key] > 1) {
            print key "\t" profiles[key]
          }
        }
      }
    ' "$records_file" | sort
  )"

  [[ -n "$duplicate_output" ]] || return 0

  while IFS=$'\t' read -r duplicate_value duplicate_profiles; do
    [[ -n "${duplicate_value:-}" ]] || continue
    printf 'DUPLICATE_%s=%s\n' "$label" "$duplicate_value"
    printf 'DUPLICATE_%s_PROFILES=%s\n' "$label" "$duplicate_profiles"
    failures=$((failures + 1))
  done <<<"$duplicate_output"
}

if [[ -s "$records_file" ]]; then
  check_duplicate_column 2 ISSUE_PREFIX
  check_duplicate_column 3 PR_PREFIX
  check_duplicate_column 4 ISSUE_BRANCH_PREFIX
  check_duplicate_column 5 PR_WORKTREE_BRANCH_PREFIX
fi

if (( failures > 0 )); then
  printf 'PROFILE_SMOKE_STATUS=failed\n'
  exit 1
fi

printf 'PROFILE_SMOKE_STATUS=ok\n'
