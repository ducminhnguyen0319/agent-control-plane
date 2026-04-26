#!/usr/bin/env bash
set -euo pipefail

HOOK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_SCRIPT_DIR}/../tools/bin/flow-config-lib.sh"

FLOW_SKILL_DIR="$(cd "${HOOK_SCRIPT_DIR}/.." && pwd)"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
ADAPTER_BIN_DIR="${FLOW_SKILL_DIR}/bin"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
: "${RUNS_ROOT:?RUNS_ROOT is required}"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
PR_WORKTREE_BRANCH_PREFIX="$(flow_resolve_pr_worktree_branch_prefix "${CONFIG_YAML}")"
PR_LANE_OVERRIDE_DIR="${STATE_ROOT}/pr-lane-overrides"

pr_kick_scheduler() {
  ACP_PROJECT_ID="${PROFILE_ID}" \
  AGENT_PROJECT_ID="${PROFILE_ID}" \
    "${FLOW_TOOLS_DIR}/kick-scheduler.sh" "${1:-2}" >/dev/null || true
}

pr_best_effort_update_labels() {
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" "$@" >/dev/null 2>&1 || true
}

pr_best_effort_sync_pr_labels() {
  "${ADAPTER_BIN_DIR}/sync-pr-labels.sh" "$1" >/dev/null 2>&1 || true
}

pr_set_lane_override() {
  local pr_number="${1:?pr number required}"
  local lane="${2:?lane required}"
  mkdir -p "${PR_LANE_OVERRIDE_DIR}"
  cat >"${PR_LANE_OVERRIDE_DIR}/${pr_number}.env" <<EOF
PR_LANE_OVERRIDE=${lane}
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

pr_clear_lane_override() {
  local pr_number="${1:?pr number required}"
  rm -f "${PR_LANE_OVERRIDE_DIR}/${pr_number}.env"
}

pr_schedule_retry() {
  local reason="${1:?reason required}"
  "${FLOW_TOOLS_DIR}/retry-state.sh" pr "$PR_NUMBER" schedule "$reason" >/dev/null || true
}

pr_clear_retry() {
  "${FLOW_TOOLS_DIR}/retry-state.sh" pr "$PR_NUMBER" clear >/dev/null || true
}

pr_linked_issue_should_close() {
  local issue_id="${1:?issue id required}"
  local issue_json
  issue_json="$(flow_github_issue_view_json "${REPO_SLUG}" "${issue_id}" 2>/dev/null || true)"
  if [[ -n "$issue_json" ]] && jq -e 'any(.labels[]?; .name == "agent-keep-open")' >/dev/null <<<"$issue_json"; then
    printf 'no\n'
  else
    printf 'yes\n'
  fi
}

pr_cleanup_linked_issue_session() {
  local issue_id="${1:-}"
  [[ -n "$issue_id" ]] || return 0

  local should_close
  should_close="$(pr_linked_issue_should_close "$issue_id")"
  update_args=(--remove agent-running --remove agent-blocked --remove agent-e2e-heavy --remove agent-automerge --remove agent-exclusive)
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$issue_id" "${update_args[@]}"
  
  # Clean up stale session state
  local issue_session="${ISSUE_SESSION_PREFIX}${issue_id}"
  local issue_meta="${RUNS_ROOT}/${issue_session}/run.env"
  if [[ -f "$issue_meta" ]]; then
    local issue_worktree
    issue_worktree="$(awk -F= '/^WORKTREE=/{print $2}' "$issue_meta" | head -n 1)"
    "${FLOW_TOOLS_DIR}/cleanup-worktree.sh" "${issue_worktree:-}" "$issue_session" >/dev/null || true
    
    # Check for stale PID files and clean them
    local pid_file="${RUNS_ROOT}/${issue_session}/pid"
    if [[ -f "$pid_file" ]]; then
      local stale_pid="$(cat "$pid_file" 2>/dev/null || true)"
      if [[ -n "$stale_pid" ]] && ! kill -0 "$stale_pid" 2>/dev/null; then
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [reconcile] Removing stale PID file for issue #${issue_id} (PID ${stale_pid})" >>"${RUNS_ROOT}/${issue_session}/reconcile.log" 2>/dev/null || true
        rm -f "$pid_file"
      fi
    fi
  fi
}

pr_cleanup_merged_residue() {
  local pr_number="${1:?pr number required}"
  local agent_repo_root="${AGENT_REPO_ROOT}"
  local cleanup_tool="${FLOW_TOOLS_DIR}/agent-cleanup-worktree"
  local temp_branch=""
  local head_ref=""

  if [[ ! -d "$agent_repo_root" ]]; then
    return 0
  fi

  git -C "$agent_repo_root" fetch --prune origin >/dev/null 2>&1 || true

  while IFS= read -r temp_branch; do
    [[ -n "$temp_branch" ]] || continue
    (
      cd "$agent_repo_root"
      "$cleanup_tool" --branch "$temp_branch" --remote "" --allow-unmerged >/dev/null
    ) || true
  done < <(git -C "$agent_repo_root" for-each-ref --format='%(refname:short)' "refs/heads/${PR_WORKTREE_BRANCH_PREFIX}-${pr_number}-*")

  head_ref="$(flow_github_pr_view_json "${REPO_SLUG}" "${pr_number}" 2>/dev/null | jq -r '.headRefName // empty' 2>/dev/null || true)"
  if [[ -n "$head_ref" ]]; then
    git -C "$agent_repo_root" branch -r -d "origin/${head_ref}" >/dev/null 2>&1 || true
  fi

  git -C "$agent_repo_root" fetch --prune origin >/dev/null 2>&1 || true
}

pr_refresh_linked_issue_checklist() {
  local pr_number="${1:?pr number required}"
  local risk_json=""
  local linked_issue_id=""

  risk_json="$("${ADAPTER_BIN_DIR}/pr-risk.sh" "$pr_number" 2>/dev/null || true)"
  [[ -n "${risk_json}" ]] || return 0

  linked_issue_id="$(jq -r '.linkedIssueId // empty' <<<"${risk_json}")"
  [[ -n "${linked_issue_id}" ]] || return 0
  [[ "$(pr_linked_issue_should_close "${linked_issue_id}")" == "no" ]] || return 0

  bash "${FLOW_TOOLS_DIR}/sync-recurring-issue-checklist.sh" \
    --repo-slug "${REPO_SLUG}" \
    --issue-id "${linked_issue_id}" >/dev/null 2>&1 || true
}

pr_after_merged() {
  local pr_number="${1:?pr number required}"
  pr_clear_lane_override "$pr_number"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-automerge --remove agent-repair-queued --remove agent-fix-needed --remove agent-manual-fix-override --remove agent-ci-refresh --remove agent-ci-bypassed --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved --remove agent-blocked --remove agent-handoff --remove agent-exclusive
  pr_refresh_linked_issue_checklist "$pr_number"
  pr_kick_scheduler 5
}

pr_after_closed() {
  local pr_number="${1:?pr number required}"
  pr_clear_lane_override "$pr_number"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-automerge --remove agent-repair-queued --remove agent-fix-needed --remove agent-manual-fix-override --remove agent-ci-refresh --remove agent-ci-bypassed --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved --remove agent-blocked --remove agent-handoff --remove agent-exclusive
  pr_kick_scheduler 5
}

pr_automerge_allowed() {
  local pr_number="${1:?pr number required}"
  local risk_json
  risk_json="$("${ADAPTER_BIN_DIR}/pr-risk.sh" "$pr_number")"
  local lane
  lane="$(jq -r '.agentLane' <<<"$risk_json")"
  if [[ "$lane" == "automerge" || "$lane" == "double-check-2" || "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" == "true" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

pr_review_pass_action() {
  local pr_number="${1:?pr number required}"
  local risk_json lane
  risk_json="$("${ADAPTER_BIN_DIR}/pr-risk.sh" "$pr_number")"
  lane="$(jq -r '.agentLane' <<<"$risk_json")"

  case "$lane" in
    double-check-1)
      printf 'advance-double-check-2\n'
      ;;
    double-check-2|automerge)
      printf 'merge\n'
      ;;
    human-review)
      printf 'wait-human\n'
      ;;
    *)
      printf 'merge\n'
      ;;
  esac
}

pr_after_double_check_advanced() {
  local pr_number="${1:?pr number required}"
  local next_stage="${2:?next stage required}"
  local next_label=""

  case "$next_stage" in
    2) next_label="agent-double-check-2/2" ;;
    *) echo "unsupported double-check stage: $next_stage" >&2; return 1 ;;
  esac

  pr_set_lane_override "$pr_number" "double-check-${next_stage}"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-automerge --remove agent-repair-queued --remove agent-fix-needed --remove agent-manual-fix-override --remove agent-ci-refresh --remove agent-human-review --remove agent-human-approved --remove agent-double-check-1/2 --remove agent-double-check-2/2 --add "$next_label"
  pr_best_effort_sync_pr_labels "$pr_number"
  pr_kick_scheduler 5
}

pr_after_updated_branch() {
  local pr_number="${1:?pr number required}"
  pr_clear_lane_override "$pr_number"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-blocked --remove agent-repair-queued --remove agent-fix-needed --remove agent-manual-fix-override --remove agent-ci-refresh --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-approved
  pr_best_effort_sync_pr_labels "$pr_number"
}

pr_after_blocked() {
  local pr_number="${1:?pr number required}"
  pr_clear_lane_override "$pr_number"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-blocked --remove agent-automerge --remove agent-ci-refresh --remove agent-ci-bypassed --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved --remove agent-fix-needed --remove agent-manual-fix-override --add agent-repair-queued
  pr_best_effort_sync_pr_labels "$pr_number"
}

pr_after_succeeded() {
  local pr_number="${1:?pr number required}"
  pr_clear_lane_override "$pr_number"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-repair-queued --remove agent-fix-needed --remove agent-manual-fix-override --remove agent-ci-refresh --remove agent-double-check-1/2 --remove agent-double-check-2/2
  pr_best_effort_sync_pr_labels "$pr_number"
}

pr_after_failed() {
  local pr_number="${1:?pr number required}"
  pr_clear_lane_override "$pr_number"
  pr_best_effort_update_labels --repo-slug "${REPO_SLUG}" --number "$pr_number" --remove agent-running --remove agent-blocked --remove agent-repair-queued --remove agent-fix-needed --remove agent-manual-fix-override --remove agent-ci-refresh --remove agent-double-check-1/2 --remove agent-double-check-2/2
  pr_best_effort_sync_pr_labels "$pr_number"
}

pr_after_reconciled() {
  pr_kick_scheduler 2
}
