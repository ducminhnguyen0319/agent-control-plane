#!/usr/bin/env bash
# heartbeat-loop-counting-lib.sh — worker counting, pending launch counts, capacity queries

running_heavy_issue_workers() {
  local session issue_id is_heavy count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    is_heavy="$(cached_issue_attr heavy "$issue_id")"
    if [[ "$is_heavy" == "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  printf '%s\n' "$count"
}

pending_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id"; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_pr_launch_count() {
  local pending_file pr_id count=0
  for pending_file in "${pending_launch_dir}"/pr-*.pid; do
    [[ -f "$pending_file" ]] || continue
    pr_id="${pending_file##*/pr-}"
    pr_id="${pr_id%.pid}"
    [[ -n "$pr_id" ]] || continue
    if tmux has-session -t "${pr_prefix}${pr_id}" 2>/dev/null; then
      continue
    fi
    if pending_pr_launch_active "$pr_id"; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_heavy_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id" && [[ "$(cached_issue_attr heavy "$issue_id")" == "yes" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_scheduled_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id" && [[ "$(cached_issue_attr scheduled "$issue_id")" == "yes" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_scheduled_heavy_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id" \
      && [[ "$(cached_issue_attr scheduled "$issue_id")" == "yes" ]] \
      && [[ "$(cached_issue_attr heavy "$issue_id")" == "yes" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_recurring_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id" \
      && [[ "$(cached_issue_attr scheduled "$issue_id")" != "yes" ]] \
      && [[ "$(cached_issue_attr recurring "$issue_id")" == "yes" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_blocked_recovery_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id" && blocked_recovery_issue_has_state "$issue_id"; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_exclusive_issue_launch_count() {
  local pending_file issue_id count=0
  for pending_file in "${pending_launch_dir}"/issue-*.pid; do
    [[ -f "$pending_file" ]] || continue
    issue_id="${pending_file##*/issue-}"
    issue_id="${issue_id%.pid}"
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_counts_toward_capacity "$issue_id" && [[ "$(cached_issue_attr exclusive "$issue_id")" == "yes" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

pending_exclusive_pr_launch_count() {
  local pending_file pr_id count=0
  for pending_file in "${pending_launch_dir}"/pr-*.pid; do
    [[ -f "$pending_file" ]] || continue
    pr_id="${pending_file##*/pr-}"
    pr_id="${pr_id%.pid}"
    [[ -n "$pr_id" ]] || continue
    if tmux has-session -t "${pr_prefix}${pr_id}" 2>/dev/null; then
      continue
    fi
    if pending_pr_launch_active "$pr_id" && [[ "$(cached_pr_is_exclusive "$pr_id")" == "yes" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

running_non_recurring_issue_workers() {
  local session issue_id is_recurring is_scheduled count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    is_scheduled="$(cached_issue_attr scheduled "$issue_id")"
    if [[ "$is_scheduled" == "yes" ]]; then
      continue
    fi
    is_recurring="$(cached_issue_attr recurring "$issue_id")"
    if [[ "$is_recurring" != "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  printf '%s\n' "$count"
}

running_recurring_issue_workers() {
  local session issue_id is_recurring is_scheduled count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    is_scheduled="$(cached_issue_attr scheduled "$issue_id")"
    if [[ "$is_scheduled" == "yes" ]]; then
      continue
    fi
    is_recurring="$(cached_issue_attr recurring "$issue_id")"
    if [[ "$is_recurring" == "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  # Also count pending recurring launches that are still in progress
  # (prevents infinite respawning when workers die before creating tmux sessions)
  count=$((count + $(pending_recurring_issue_launch_count)))
  printf '%s\n' "$count"
}

running_blocked_recovery_issue_workers() {
  local session issue_id count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    if blocked_recovery_issue_has_state "$issue_id"; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  printf '%s\n' "$count"
}

running_exclusive_issue_workers() {
  local session issue_id is_exclusive count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    is_exclusive="$(cached_issue_attr exclusive "$issue_id")"
    if [[ "$is_exclusive" == "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  printf '%s\n' "$count"
}

running_exclusive_pr_workers() {
  local session pr_id is_exclusive count=0
  ensure_running_pr_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    pr_id="$(pr_id_from_session "$session" || true)"
    [[ -n "$pr_id" ]] || continue
    is_exclusive="$(cached_pr_is_exclusive "$pr_id")"
    if [[ "$is_exclusive" == "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_pr_workers_cache"
  printf '%s\n' "$count"
}

running_scheduled_issue_workers() {
  local session issue_id is_scheduled count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    is_scheduled="$(cached_issue_attr scheduled "$issue_id")"
    if [[ "$is_scheduled" == "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  printf '%s\n' "$count"
}

running_scheduled_heavy_issue_workers() {
  local session issue_id is_scheduled is_heavy count=0
  ensure_running_issue_workers_cache
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    issue_id="$(issue_id_from_session "$session" || true)"
    [[ -n "$issue_id" ]] || continue
    is_scheduled="$(cached_issue_attr scheduled "$issue_id")"
    is_heavy="$(cached_issue_attr heavy "$issue_id")"
    if [[ "$is_scheduled" == "yes" && "$is_heavy" == "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$running_issue_workers_cache"
  printf '%s\n' "$count"
}

ready_non_recurring_issue_count() {
  local issue_id is_recurring count=0
  ensure_ready_issue_ids_cache
  while IFS= read -r issue_id; do
    [[ -n "$issue_id" ]] || continue
    if [[ "$(cached_issue_attr scheduled "$issue_id")" == "yes" ]]; then
      continue
    fi
    is_recurring="$(cached_issue_attr recurring "$issue_id")"
    if [[ "$is_recurring" != "yes" ]]; then
      count=$((count + 1))
    fi
  done <<<"$ready_issue_ids_cache"
  printf '%s\n' "$count"
}
