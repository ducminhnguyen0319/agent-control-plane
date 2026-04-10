#!/usr/bin/env bash
# heartbeat-loop-pr-strategy-lib.sh — PR candidate selection and strategy.
#
# Implements the priority-ordered lane dispatch for PR workers:
# double-check-2 > double-check-1 > automerge > merge-repair > fix > ci-refresh.
#
# Depends on: heartbeat-loop-worker-lib.sh, heartbeat-loop-cache-lib.sh,
#             heartbeat-loop-scheduling-lib.sh

next_pr_candidate_json() {
  local target_lane pr_number risk_json lane
  ensure_open_agent_pr_ids_cache
  for target_lane in double-check-2 double-check-1 automerge merge-repair fix ci-refresh; do
    while IFS= read -r pr_number; do
      [[ -n "$pr_number" ]] || continue
      if tmux has-session -t "${pr_prefix}${pr_number}" 2>/dev/null; then
        continue
      fi
      if pr_launch_reserved "$pr_number"; then
        continue
      fi
      if pending_pr_launch_active "$pr_number"; then
        continue
      fi
      if ! retry_ready pr "$pr_number"; then
        continue
      fi
      risk_json="$(cached_pr_risk_json "$pr_number")"
      lane="$(jq -r '.agentLane' <<<"$risk_json")"
      if [[ "$lane" == "$target_lane" ]]; then
        printf '%s\n' "$risk_json"
        return 0
      fi
    done <<<"$open_agent_pr_ids_cache"
  done
}

next_priority_review_pr_candidate_json() {
  local target_lane pr_number risk_json lane
  ensure_open_agent_pr_ids_cache
  for target_lane in double-check-2 double-check-1; do
    while IFS= read -r pr_number; do
      [[ -n "$pr_number" ]] || continue
      if tmux has-session -t "${pr_prefix}${pr_number}" 2>/dev/null; then
        continue
      fi
      if pr_launch_reserved "$pr_number"; then
        continue
      fi
      if pending_pr_launch_active "$pr_number"; then
        continue
      fi
      if ! retry_ready pr "$pr_number"; then
        continue
      fi
      risk_json="$(cached_pr_risk_json "$pr_number")"
      lane="$(jq -r '.agentLane' <<<"$risk_json")"
      if [[ "$lane" == "$target_lane" ]]; then
        printf '%s\n' "$risk_json"
        return 0
      fi
    done <<<"$open_agent_pr_ids_cache"
  done
}

eligible_pr_backlog_count() {
  local pr_number risk_json lane count=0
  ensure_open_agent_pr_ids_cache
  while IFS= read -r pr_number; do
    [[ -n "$pr_number" ]] || continue
    if tmux has-session -t "${pr_prefix}${pr_number}" 2>/dev/null; then
      continue
    fi
    if pr_launch_reserved "$pr_number"; then
      continue
    fi
    if pending_pr_launch_active "$pr_number"; then
      continue
    fi
    if ! retry_ready pr "$pr_number"; then
      continue
    fi
    risk_json="$(cached_pr_risk_json "$pr_number")"
    lane="$(jq -r '.agentLane' <<<"$risk_json")"
    case "$lane" in
      double-check-1|double-check-2|automerge|merge-repair|fix)
        count=$((count + 1))
        ;;
    esac
  done <<<"$open_agent_pr_ids_cache"
  printf '%s\n' "$count"
}

priority_review_backlog_count() {
  local pr_number risk_json lane count=0
  ensure_open_agent_pr_ids_cache
  while IFS= read -r pr_number; do
    [[ -n "$pr_number" ]] || continue
    if tmux has-session -t "${pr_prefix}${pr_number}" 2>/dev/null; then
      continue
    fi
    if pr_launch_reserved "$pr_number"; then
      continue
    fi
    if pending_pr_launch_active "$pr_number"; then
      continue
    fi
    if ! retry_ready pr "$pr_number"; then
      continue
    fi
    risk_json="$(cached_pr_risk_json "$pr_number")"
    lane="$(jq -r '.agentLane' <<<"$risk_json")"
    case "$lane" in
      double-check-1|double-check-2)
        count=$((count + 1))
        ;;
    esac
  done <<<"$open_agent_pr_ids_cache"
  printf '%s\n' "$count"
}

next_exclusive_pr_candidate_json() {
  local target_lane pr_number risk_json lane
  ensure_exclusive_pr_ids_cache
  for target_lane in double-check-2 double-check-1 automerge merge-repair fix ci-refresh; do
    while IFS= read -r pr_number; do
      [[ -n "$pr_number" ]] || continue
      if tmux has-session -t "${pr_prefix}${pr_number}" 2>/dev/null; then
        continue
      fi
      if pr_launch_reserved "$pr_number"; then
        continue
      fi
      if pending_pr_launch_active "$pr_number"; then
        continue
      fi
      if ! retry_ready pr "$pr_number"; then
        continue
      fi
      risk_json="$(cached_pr_risk_json "$pr_number")"
      lane="$(jq -r '.agentLane' <<<"$risk_json")"
      # Skip PRs requiring human review; they should not hold exclusive lock
      if [[ "$lane" == "human-review" ]]; then
        continue
      fi
      if [[ "$lane" == "$target_lane" ]]; then
        printf '%s\n' "$risk_json"
        return 0
      fi
    done <<<"$exclusive_pr_ids_cache"
  done
}

next_exclusive_issue_id() {
  local issue_id
  ensure_exclusive_issue_ids_cache
  while IFS= read -r issue_id; do
    [[ -n "$issue_id" ]] || continue
    if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
      continue
    fi
    if pending_issue_launch_active "$issue_id"; then
      continue
    fi
    if ! retry_ready issue "$issue_id"; then
      continue
    fi
    printf '%s\n' "$issue_id"
    return 0
  done <<<"$exclusive_issue_ids_cache"
}

count_pr_lane() {
  local target_lane="${1:?target lane required}"
  local pr_number risk_json lane count=0
  ensure_open_agent_pr_ids_cache
  while IFS= read -r pr_number; do
    [[ -n "$pr_number" ]] || continue
    risk_json="$(cached_pr_risk_json "$pr_number")"
    lane="$(jq -r '.agentLane' <<<"$risk_json")"
    if [[ "$lane" == "$target_lane" ]]; then
      count=$((count + 1))
    fi
  done <<<"$open_agent_pr_ids_cache"
  printf '%s\n' "$count"
}

human_review_pr_ids() {
  local pr_number risk_json lane
  ensure_open_agent_pr_ids_cache
  while IFS= read -r pr_number; do
    [[ -n "$pr_number" ]] || continue
    risk_json="$(cached_pr_risk_json "$pr_number")"
    lane="$(jq -r '.agentLane' <<<"$risk_json")"
    if [[ "$lane" == "human-review" ]]; then
      printf '%s\n' "$pr_number"
    fi
  done <<<"$open_agent_pr_ids_cache"
}
