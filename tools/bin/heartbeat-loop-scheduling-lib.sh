#!/usr/bin/env bash
# heartbeat-loop-scheduling-lib.sh — Issue scheduling, ordering, and sync.
#
# Manages scheduled issues (cron-like), blocked-recovery queue, recurring
# issue rotation, issue/PR ID caching, and open-agent sync.
#
# Depends on: heartbeat-loop-worker-lib.sh, heartbeat-loop-cache-lib.sh

blocked_recovery_issue_ids() {
  ensure_blocked_recovery_issue_ids_cache
  printf '%s\n' "$blocked_recovery_issue_ids_cache"
}

ordered_ready_issue_ids() {
  ensure_ordered_ready_issue_ids_cache
  printf '%s\n' "$ordered_ready_issue_ids_cache"
}

due_scheduled_issue_ids() {
  ensure_due_scheduled_issue_ids_cache
  printf '%s\n' "$due_scheduled_issue_ids_cache"
}

due_blocked_recovery_issue_ids() {
  ensure_due_blocked_recovery_issue_ids_cache
  printf '%s\n' "$due_blocked_recovery_issue_ids_cache"
}

ensure_due_scheduled_issue_ids_cache() {
  if [[ "$due_scheduled_issue_ids_cache_loaded" != "yes" ]]; then
    due_scheduled_issue_ids_cache="$(build_due_scheduled_issue_ids_cache)"
    due_scheduled_issue_ids_cache_loaded="yes"
  fi
}

ensure_due_blocked_recovery_issue_ids_cache() {
  if [[ "$due_blocked_recovery_issue_ids_cache_loaded" != "yes" ]]; then
    due_blocked_recovery_issue_ids_cache="$(build_due_blocked_recovery_issue_ids_cache)"
    due_blocked_recovery_issue_ids_cache_loaded="yes"
  fi
}

build_due_scheduled_issue_ids_cache() {
  local issue_id now_epoch due_epoch
  now_epoch="$(date +%s)"
  ensure_ready_issue_ids_cache
  while IFS= read -r issue_id; do
    [[ -n "$issue_id" ]] || continue
    if [[ "$(cached_issue_attr scheduled "$issue_id")" != "yes" ]]; then
      continue
    fi
    if ! scheduled_issue_is_due "$issue_id"; then
      continue
    fi
    due_epoch="$(scheduled_issue_due_epoch "$issue_id")"
    if ! [[ "${due_epoch:-}" =~ ^[0-9]+$ ]]; then
      due_epoch=0
    fi
    printf '%s\t%s\n' "$due_epoch" "$issue_id"
  done <<<"$ready_issue_ids_cache" | sort -n -k1,1 -k2,2n | cut -f2
}

build_due_blocked_recovery_issue_ids_cache() {
  local issue_id due_epoch
  if (( max_concurrent_blocked_recovery_issue_workers <= 0 )); then
    return 0
  fi

  ensure_blocked_recovery_issue_ids_cache
  while IFS= read -r issue_id; do
    [[ -n "$issue_id" ]] || continue
    if ! blocked_recovery_issue_is_due "$issue_id"; then
      continue
    fi
    due_epoch="$(blocked_recovery_issue_due_epoch "$issue_id")"
    if ! [[ "${due_epoch:-}" =~ ^[0-9]+$ ]]; then
      due_epoch=0
    fi
    printf '%s\t%s\n' "$due_epoch" "$issue_id"
  done <<<"$blocked_recovery_issue_ids_cache" | sort -n -k1,1 -k2,2n | cut -f2
}

build_ordered_ready_issue_ids_cache() {
  local issue_id is_recurring last_recurring_issue seen_last="no"
  local -a recurring_ids=()
  ensure_ready_issue_ids_cache
  while IFS= read -r issue_id; do
    [[ -n "$issue_id" ]] || continue
    if [[ "$(cached_issue_attr scheduled "$issue_id")" == "yes" ]]; then
      continue
    fi
    is_recurring="$(cached_issue_attr recurring "$issue_id")"
    if [[ "$is_recurring" != "yes" ]]; then
      printf '%s\n' "$issue_id"
    else
      recurring_ids+=("$issue_id")
    fi
  done <<<"$ready_issue_ids_cache"

  if (( ${#recurring_ids[@]} == 0 )); then
    return 0
  fi

  last_recurring_issue="$(last_launched_recurring_issue_id || true)"
  if [[ -n "$last_recurring_issue" ]]; then
    local emitted_after_last=0
    for issue_id in "${recurring_ids[@]}"; do
      if [[ "$seen_last" == "yes" ]]; then
        printf '%s\n' "$issue_id"
        emitted_after_last=$((emitted_after_last + 1))
      fi
      if [[ "$issue_id" == "$last_recurring_issue" ]]; then
        seen_last="yes"
      fi
    done
  fi

  for issue_id in "${recurring_ids[@]}"; do
    # Stop the wrap-around once we reach the last-launched issue, but only
    # when the first loop already emitted at least one issue after it.
    # When there is exactly one recurring issue (or the last-launched issue
    # is the final element), emitted_after_last is 0, so we must still
    # include it here to avoid producing an empty list.
    if [[ -n "$last_recurring_issue" && "$seen_last" == "yes" && "$issue_id" == "$last_recurring_issue" && "$emitted_after_last" -gt 0 ]]; then
      break
    fi
    printf '%s\n' "$issue_id"
  done
}

completed_workers() {
  ensure_completed_workers_cache
  printf '%s\n' "$completed_workers_cache"
}

reconciled_marker_matches_run() {
  local run_dir="${1:?run dir required}"
  local marker_file="${run_dir}/reconciled.ok"
  local run_env="${run_dir}/run.env"
  local marker_started_at=""
  local run_started_at=""

  [[ -f "${marker_file}" && -f "${run_env}" ]] || return 1

  marker_started_at="$(awk -F= '/^STARTED_AT=/{print $2}' "${marker_file}" 2>/dev/null | tr -d '"' | tail -n 1 || true)"
  run_started_at="$(awk -F= '/^STARTED_AT=/{print $2}' "${run_env}" 2>/dev/null | tr -d '"' | tail -n 1 || true)"

  [[ -n "${marker_started_at}" && -n "${run_started_at}" && "${marker_started_at}" == "${run_started_at}" ]]
}

ensure_completed_workers_cache() {
  local dir session issue_id status_line status
  if [[ "$completed_workers_cache_loaded" == "yes" ]]; then
    return 0
  fi
  completed_workers_cache=""
  for dir in "$runs_root"/*; do
    [[ -d "$dir" ]] || continue
    session="${dir##*/}"
    session_matches_prefix "$session" || continue
    if reconciled_marker_matches_run "$dir"; then
      continue
    fi
    if [[ "$session" == "${issue_prefix}"* ]]; then
      issue_id="$(issue_id_from_session "$session" || true)"
      if [[ -n "${issue_id}" ]] && pending_issue_launch_active "${issue_id}"; then
        continue
      fi
    fi
    status_line="$(
      "${shared_agent_home}/tools/bin/agent-project-worker-status" \
        --runs-root "$runs_root" \
        --session "$session" \
        | awk -F= '/^STATUS=/{print $2}' || true
    )"
    status="${status_line:-UNKNOWN}"
    if [[ "$status" == "SUCCEEDED" || "$status" == "FAILED" ]]; then
      completed_workers_cache+="${session}"$'\n'
    fi
  done
  completed_workers_cache="${completed_workers_cache%$'\n'}"
  completed_workers_cache_loaded="yes"
}

ready_issue_ids() {
  ensure_ready_issue_ids_cache
  printf '%s\n' "$ready_issue_ids_cache"
}

ensure_ready_issue_ids_cache() {
  if [[ "$ready_issue_ids_cache_loaded" != "yes" ]]; then
    ready_issue_ids_cache="$(heartbeat_list_ready_issue_ids)"
    ready_issue_ids_cache_loaded="yes"
  fi
}

last_launched_recurring_issue_id() {
  if [[ -f "$recurring_rotation_file" ]]; then
    tr -d '[:space:]' <"$recurring_rotation_file"
  fi
}

record_recurring_issue_launch() {
  local issue_id="${1:?issue id required}"
  printf '%s\n' "$issue_id" >"$recurring_rotation_file"
}

scheduled_state_file() {
  local issue_id="${1:?issue id required}"
  printf '%s\n' "${scheduled_state_dir}/${issue_id}.env"
}

scheduled_issue_due_epoch() {
  local issue_id="${1:?issue id required}"
  local state_file next_due_epoch
  state_file="$(scheduled_state_file "$issue_id")"
  if [[ ! -f "$state_file" ]]; then
    printf '0\n'
    return 0
  fi

  next_due_epoch="$(awk -F= '/^NEXT_DUE_EPOCH=/{print $2}' "$state_file" 2>/dev/null | tr -d '[:space:]' || true)"
  if ! [[ "${next_due_epoch:-}" =~ ^[0-9]+$ ]]; then
    printf '0\n'
    return 0
  fi

  printf '%s\n' "$next_due_epoch"
}

scheduled_issue_is_due() {
  local issue_id="${1:?issue id required}"
  local interval_seconds due_epoch now_epoch
  interval_seconds="$(cached_issue_attr schedule_interval_seconds "$issue_id")"
  if ! [[ "${interval_seconds:-}" =~ ^[1-9][0-9]*$ ]]; then
    return 1
  fi

  due_epoch="$(scheduled_issue_due_epoch "$issue_id")"
  now_epoch="$(date +%s)"
  if ! [[ "${due_epoch:-}" =~ ^[0-9]+$ ]] || (( due_epoch == 0 || due_epoch <= now_epoch )); then
    return 0
  fi
  return 1
}

record_scheduled_issue_launch() {
  local issue_id="${1:?issue id required}"
  local interval_seconds state_file now_epoch due_epoch next_due_epoch

  interval_seconds="$(cached_issue_attr schedule_interval_seconds "$issue_id")"
  if ! [[ "${interval_seconds:-}" =~ ^[1-9][0-9]*$ ]]; then
    return 0
  fi

  now_epoch="$(date +%s)"
  due_epoch="$(scheduled_issue_due_epoch "$issue_id")"
  if ! [[ "${due_epoch:-}" =~ ^[0-9]+$ ]] || (( due_epoch <= 0 )); then
    next_due_epoch=$((now_epoch + interval_seconds))
  else
    next_due_epoch="$due_epoch"
    while (( next_due_epoch <= now_epoch )); do
      next_due_epoch=$((next_due_epoch + interval_seconds))
    done
  fi

  state_file="$(scheduled_state_file "$issue_id")"
  cat >"$state_file" <<EOF
INTERVAL_SECONDS=${interval_seconds}
LAST_STARTED_EPOCH=${now_epoch}
LAST_STARTED_AT=$(flow_format_epoch_utc "$now_epoch")
NEXT_DUE_EPOCH=${next_due_epoch}
NEXT_DUE_AT=$(flow_format_epoch_utc "$next_due_epoch")
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

record_scheduled_issue_result() {
  local issue_id="${1:?issue id required}"
  local result_status="${2:-unknown}"
  local state_file interval_seconds last_started_epoch next_due_epoch now_epoch

  state_file="$(scheduled_state_file "$issue_id")"
  interval_seconds="$(cached_issue_attr schedule_interval_seconds "$issue_id")"
  last_started_epoch="$(awk -F= '/^LAST_STARTED_EPOCH=/{print $2}' "$state_file" 2>/dev/null | tr -d '[:space:]' || true)"
  next_due_epoch="$(awk -F= '/^NEXT_DUE_EPOCH=/{print $2}' "$state_file" 2>/dev/null | tr -d '[:space:]' || true)"
  now_epoch="$(date +%s)"

  if ! [[ "${interval_seconds:-}" =~ ^[1-9][0-9]*$ ]]; then
    interval_seconds=0
  fi
  if ! [[ "${last_started_epoch:-}" =~ ^[0-9]+$ ]]; then
    last_started_epoch=0
  fi
  if ! [[ "${next_due_epoch:-}" =~ ^[0-9]+$ ]]; then
    next_due_epoch=0
  fi

  cat >"$state_file" <<EOF
INTERVAL_SECONDS=${interval_seconds}
LAST_STARTED_EPOCH=${last_started_epoch}
LAST_STARTED_AT=$(if [[ "$last_started_epoch" =~ ^[0-9]+$ ]] && (( last_started_epoch > 0 )); then flow_format_epoch_utc "$last_started_epoch"; fi)
LAST_RESULT_STATUS=${result_status}
LAST_RESULT_EPOCH=${now_epoch}
LAST_RESULT_AT=$(flow_format_epoch_utc "$now_epoch")
NEXT_DUE_EPOCH=${next_due_epoch}
NEXT_DUE_AT=$(if [[ "$next_due_epoch" =~ ^[0-9]+$ ]] && (( next_due_epoch > 0 )); then flow_format_epoch_utc "$next_due_epoch"; fi)
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

blocked_recovery_state_file() {
  local issue_id="${1:?issue id required}"
  printf '%s\n' "${blocked_recovery_state_dir}/${issue_id}.env"
}

blocked_recovery_issue_has_state() {
  local issue_id="${1:?issue id required}"
  [[ -f "$(blocked_recovery_state_file "$issue_id")" ]]
}

blocked_recovery_issue_due_epoch() {
  local issue_id="${1:?issue id required}"
  local state_file next_due_epoch
  state_file="$(blocked_recovery_state_file "$issue_id")"
  if [[ ! -f "$state_file" ]]; then
    printf '0\n'
    return 0
  fi

  next_due_epoch="$(awk -F= '/^NEXT_DUE_EPOCH=/{print $2}' "$state_file" 2>/dev/null | tr -d '[:space:]' || true)"
  if ! [[ "${next_due_epoch:-}" =~ ^[0-9]+$ ]]; then
    printf '0\n'
    return 0
  fi

  printf '%s\n' "$next_due_epoch"
}

blocked_recovery_issue_is_due() {
  local issue_id="${1:?issue id required}"
  local due_epoch now_epoch
  if ! [[ "${blocked_recovery_cooldown_seconds:-}" =~ ^[1-9][0-9]*$ ]]; then
    return 0
  fi

  due_epoch="$(blocked_recovery_issue_due_epoch "$issue_id")"
  now_epoch="$(date +%s)"
  if ! [[ "${due_epoch:-}" =~ ^[0-9]+$ ]] || (( due_epoch == 0 || due_epoch <= now_epoch )); then
    return 0
  fi
  return 1
}

record_blocked_recovery_issue_launch() {
  local issue_id="${1:?issue id required}"
  local state_file now_epoch next_due_epoch next_due_at

  now_epoch="$(date +%s)"
  next_due_epoch=0
  next_due_at=""
  if [[ "${blocked_recovery_cooldown_seconds:-}" =~ ^[1-9][0-9]*$ ]]; then
    next_due_epoch=$((now_epoch + blocked_recovery_cooldown_seconds))
    next_due_at="$(flow_format_epoch_utc "$next_due_epoch")"
  fi

  state_file="$(blocked_recovery_state_file "$issue_id")"
  cat >"$state_file" <<EOF
LANE=blocked-recovery
LAST_STARTED_EPOCH=${now_epoch}
LAST_STARTED_AT=$(flow_format_epoch_utc "$now_epoch")
NEXT_DUE_EPOCH=${next_due_epoch}
NEXT_DUE_AT=${next_due_at}
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

clear_blocked_recovery_issue_state() {
  local issue_id="${1:?issue id required}"
  rm -f "$(blocked_recovery_state_file "$issue_id")"
}

open_agent_pr_ids() {
  ensure_open_agent_pr_ids_cache
  printf '%s\n' "$open_agent_pr_ids_cache"
}

ensure_open_agent_pr_ids_cache() {
  if [[ "$open_agent_pr_ids_cache_loaded" != "yes" ]]; then
    open_agent_pr_ids_cache="$(heartbeat_list_open_agent_pr_ids)"
    open_agent_pr_ids_cache_loaded="yes"
  fi
}

running_issue_ids() {
  ensure_running_issue_ids_cache
  printf '%s\n' "$running_issue_ids_cache"
}

exclusive_issue_ids() {
  ensure_exclusive_issue_ids_cache
  printf '%s\n' "$exclusive_issue_ids_cache"
}

exclusive_pr_ids() {
  ensure_exclusive_pr_ids_cache
  printf '%s\n' "$exclusive_pr_ids_cache"
}

ensure_running_issue_ids_cache() {
  if [[ "$running_issue_ids_cache_loaded" != "yes" ]]; then
    running_issue_ids_cache="$(heartbeat_list_running_issue_ids)"
    running_issue_ids_cache_loaded="yes"
  fi
}

ensure_exclusive_issue_ids_cache() {
  if [[ "$exclusive_issue_ids_cache_loaded" != "yes" ]]; then
    exclusive_issue_ids_cache="$(heartbeat_list_exclusive_issue_ids)"
    exclusive_issue_ids_cache_loaded="yes"
  fi
}

ensure_exclusive_pr_ids_cache() {
  if [[ "$exclusive_pr_ids_cache_loaded" != "yes" ]]; then
    exclusive_pr_ids_cache="$(heartbeat_list_exclusive_pr_ids)"
    exclusive_pr_ids_cache_loaded="yes"
  fi
}

ensure_ordered_ready_issue_ids_cache() {
  if [[ "$ordered_ready_issue_ids_cache_loaded" != "yes" ]]; then
    ordered_ready_issue_ids_cache="$(build_ordered_ready_issue_ids_cache)"
    ordered_ready_issue_ids_cache_loaded="yes"
  fi
}

ensure_blocked_recovery_issue_ids_cache() {
  if [[ "$blocked_recovery_issue_ids_cache_loaded" != "yes" ]]; then
    blocked_recovery_issue_ids_cache="$(heartbeat_list_blocked_recovery_issue_ids)"
    blocked_recovery_issue_ids_cache_loaded="yes"
  fi
}

sync_open_agent_issues() {
  local issue_id status_out status
  ensure_running_issue_ids_cache
  while IFS= read -r issue_id; do
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_active "$issue_id"; then
      if pending_issue_launch_counts_toward_capacity "$issue_id"; then
        heartbeat_mark_issue_running "$issue_id" "$(cached_issue_attr heavy "$issue_id")" >/dev/null || true
      fi
      continue
    fi
    status_out="$(
      "${shared_agent_home}/tools/bin/agent-project-worker-status" \
        --runs-root "$runs_root" \
        --session "${issue_prefix}${issue_id}"
    )"
    status="$(awk -F= '/^STATUS=/{print $2}' <<<"$status_out")"
    case "$status" in
      RUNNING)
        ;;
      *)
        heartbeat_sync_issue_labels "$issue_id" >/dev/null || true
        ;;
    esac
  done <<<"$running_issue_ids_cache"
}

sync_open_agent_prs() {
  local pr_number status_out status
  ensure_open_agent_pr_ids_cache
  while IFS= read -r pr_number; do
    [[ -n "$pr_number" ]] || continue
    if tmux has-session -t "${pr_prefix}${pr_number}" 2>/dev/null; then
      continue
    fi
    if pending_pr_launch_active "$pr_number"; then
      heartbeat_mark_pr_running "$pr_number" >/dev/null || true
      continue
    fi
    status_out="$(
      "${shared_agent_home}/tools/bin/agent-project-worker-status" \
        --runs-root "$runs_root" \
        --session "${pr_prefix}${pr_number}"
    )"
    status="$(awk -F= '/^STATUS=/{print $2}' <<<"$status_out")"
    case "$status" in
      UNKNOWN)
        heartbeat_clear_pr_running "$pr_number" >/dev/null || true
        heartbeat_sync_pr_labels "$pr_number" >/dev/null || true
        ;;
      RUNNING)
        ;;
      *)
        heartbeat_clear_pr_running "$pr_number" >/dev/null || true
        heartbeat_sync_pr_labels "$pr_number" >/dev/null || true
        ;;
    esac
  done <<<"$open_agent_pr_ids_cache"
}
