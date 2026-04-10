#!/usr/bin/env bash
# heartbeat-loop-cache-lib.sh — scheduler cache management and attribute caching

cleanup_scheduler_caches() {
  tmux_sessions_cache=""
  tmux_sessions_cache_loaded="no"
  all_running_workers_cache=""
  all_running_workers_cache_loaded="no"
  running_issue_workers_cache=""
  running_issue_workers_cache_loaded="no"
  running_pr_workers_cache=""
  running_pr_workers_cache_loaded="no"
  completed_workers_cache=""
  completed_workers_cache_loaded="no"
  ready_issue_ids_cache=""
  ready_issue_ids_cache_loaded="no"
  open_agent_pr_ids_cache=""
  open_agent_pr_ids_cache_loaded="no"
  running_issue_ids_cache=""
  running_issue_ids_cache_loaded="no"
  exclusive_issue_ids_cache=""
  exclusive_issue_ids_cache_loaded="no"
  exclusive_pr_ids_cache=""
  exclusive_pr_ids_cache_loaded="no"
  blocked_recovery_issue_ids_cache=""
  blocked_recovery_issue_ids_cache_loaded="no"
  ordered_ready_issue_ids_cache=""
  ordered_ready_issue_ids_cache_loaded="no"
  due_scheduled_issue_ids_cache=""
  due_scheduled_issue_ids_cache_loaded="no"
  due_blocked_recovery_issue_ids_cache=""
  due_blocked_recovery_issue_ids_cache_loaded="no"
  if [[ -n "${issue_attr_cache_dir:-}" && -d "${issue_attr_cache_dir}" ]]; then
    rm -rf "${issue_attr_cache_dir}" || true
  fi
  if [[ -n "${pr_attr_cache_dir:-}" && -d "${pr_attr_cache_dir}" ]]; then
    rm -rf "${pr_attr_cache_dir}" || true
  fi
  if [[ -n "${pr_risk_cache_dir:-}" && -d "${pr_risk_cache_dir}" ]]; then
    rm -rf "${pr_risk_cache_dir}" || true
  fi
  if declare -F heartbeat_invalidate_snapshot_cache >/dev/null 2>&1; then
    heartbeat_invalidate_snapshot_cache
  fi
}

cache_prefix() {
  local raw_prefix="${issue_prefix:-${pr_prefix:-agent-control-plane}}"
  local sanitized=""

  sanitized="$(printf '%s' "${raw_prefix}" | tr '/[:space:]' '-' | tr -cd '[:alnum:]_.-')"
  if [[ -z "${sanitized}" ]]; then
    sanitized="agent-control-plane"
  fi

  printf '%s\n' "${sanitized}"
}

ensure_issue_attr_cache_dir() {
  if [[ -z "${issue_attr_cache_dir:-}" || ! -d "${issue_attr_cache_dir:-}" ]]; then
    issue_attr_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/$(cache_prefix)-issue-attrs.XXXXXX")"
  fi
}

ensure_pr_attr_cache_dir() {
  if [[ -z "${pr_attr_cache_dir:-}" || ! -d "${pr_attr_cache_dir:-}" ]]; then
    pr_attr_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/$(cache_prefix)-pr-attrs.XXXXXX")"
  fi
}

ensure_pr_risk_cache_dir() {
  if [[ -z "${pr_risk_cache_dir:-}" || ! -d "${pr_risk_cache_dir:-}" ]]; then
    pr_risk_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/$(cache_prefix)-pr-risk.XXXXXX")"
  fi
}

pr_risk_runtime_cache_fresh() {
  local cache_file="${1:?cache file required}"
  local modified_at now age
  [[ -f "$cache_file" ]] || return 1
  modified_at="$(stat -f '%m' "$cache_file" 2>/dev/null || true)"
  [[ "$modified_at" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  age=$((now - modified_at))
  (( age >= 0 && age <= pr_risk_runtime_cache_ttl_seconds ))
}

cached_issue_attr() {
  local attr_name="${1:?attr name required}"
  local issue_id="${2:?issue id required}"
  local cache_file attr_value

  ensure_issue_attr_cache_dir
  cache_file="${issue_attr_cache_dir}/${issue_id}.${attr_name}"
  if [[ -f "${cache_file}" ]]; then
    cat "${cache_file}"
    return 0
  fi

  case "${attr_name}" in
    heavy)
      attr_value="$(heartbeat_issue_is_heavy "${issue_id}")"
      ;;
    recurring)
      attr_value="$(heartbeat_issue_is_recurring "${issue_id}")"
      ;;
    scheduled)
      attr_value="$(heartbeat_issue_is_scheduled "${issue_id}")"
      ;;
    schedule_interval_seconds)
      attr_value="$(heartbeat_issue_schedule_interval_seconds "${issue_id}")"
      ;;
    exclusive)
      attr_value="$(heartbeat_issue_is_exclusive "${issue_id}")"
      ;;
    *)
      echo "unsupported issue cache attr: ${attr_name}" >&2
      return 1
      ;;
  esac

  printf '%s\n' "${attr_value}" >"${cache_file}"
  printf '%s\n' "${attr_value}"
}

cached_pr_is_exclusive() {
  local pr_number="${1:?pr number required}"
  local cache_file attr_value

  ensure_pr_attr_cache_dir
  cache_file="${pr_attr_cache_dir}/${pr_number}.exclusive"
  if [[ -f "${cache_file}" ]]; then
    cat "${cache_file}"
    return 0
  fi

  attr_value="$(heartbeat_pr_is_exclusive "${pr_number}")"
  printf '%s\n' "${attr_value}" >"${cache_file}"
  printf '%s\n' "${attr_value}"
}

cached_pr_risk_json() {
  local pr_number="${1:?pr number required}"
  local cache_file runtime_cache_file risk_json

  ensure_pr_risk_cache_dir
  cache_file="${pr_risk_cache_dir}/${pr_number}.json"
  runtime_cache_file="${pr_risk_runtime_cache_dir}/${pr_number}.json"
  if [[ -f "${cache_file}" ]]; then
    cat "${cache_file}"
    return 0
  fi

  if pr_risk_runtime_cache_fresh "${runtime_cache_file}"; then
    cp "${runtime_cache_file}" "${cache_file}"
    cat "${cache_file}"
    return 0
  fi

  risk_json="$(heartbeat_pr_risk_json "${pr_number}")"
  printf '%s\n' "${risk_json}" >"${cache_file}"
  printf '%s\n' "${risk_json}" >"${runtime_cache_file}"
  printf '%s\n' "${risk_json}"
}
