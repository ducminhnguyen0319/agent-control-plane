#!/usr/bin/env bash
# heartbeat-loop-worker-lib.sh — tmux session queries, worker enumeration, and cache helpers

all_tmux_sessions() {
  ensure_tmux_sessions_cache
  printf '%s\n' "$tmux_sessions_cache"
}

session_matches_prefix() {
  local session="${1:?session required}"
  [[ "$session" == "${issue_prefix}"* || "$session" == "${pr_prefix}"* ]]
}

session_runner_state() {
  local session="${1:?session required}"
  local runner_state_file="${runs_root}/${session}/runner.env"
  if [[ ! -f "$runner_state_file" ]]; then
    return 1
  fi
  awk -F= '/^RUNNER_STATE=/{print $2; exit}' "$runner_state_file"
}

session_is_auth_waiting() {
  local session="${1:?session required}"
  local runner_state=""
  runner_state="$(session_runner_state "$session" || true)"
  [[ "$runner_state" == "waiting-auth-refresh" || "$runner_state" == "switching-account" ]]
}

all_running_workers() {
  ensure_all_running_workers_cache
  printf '%s\n' "$all_running_workers_cache"
}

running_issue_workers() {
  ensure_running_issue_workers_cache
  printf '%s\n' "$running_issue_workers_cache"
}

running_pr_workers() {
  ensure_running_pr_workers_cache
  printf '%s\n' "$running_pr_workers_cache"
}

auth_wait_workers() {
  ensure_auth_wait_workers_cache
  printf '%s\n' "$auth_wait_workers_cache"
}

pending_launch_pid() {
  local kind="${1:?kind required}"
  local item_id="${2:?item id required}"
  local pending_file pid

  pending_file="${pending_launch_dir}/${kind}-${item_id}.pid"
  if [[ ! -f "$pending_file" ]]; then
    return 1
  fi

  pid="$(tr -d '[:space:]' <"$pending_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    rm -f "$pending_file"
    return 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    printf '%s\n' "$pid"
    return 0
  fi

  rm -f "$pending_file"
  return 1
}

pending_issue_launch_active() {
  local issue_id="${1:?issue id required}"
  if tmux has-session -t "${issue_prefix}${issue_id}" 2>/dev/null; then
    rm -f "${pending_launch_dir}/issue-${issue_id}.pid" 2>/dev/null || true
    return 1
  fi
  pending_launch_pid issue "$issue_id" >/dev/null
}

pending_pr_launch_active() {
  local pr_id="${1:?pr id required}"
  if tmux has-session -t "${pr_prefix}${pr_id}" 2>/dev/null; then
    rm -f "${pending_launch_dir}/pr-${pr_id}.pid" 2>/dev/null || true
    return 1
  fi
  pending_launch_pid pr "$pr_id" >/dev/null
}

pending_issue_launch_counts_toward_capacity() {
  local issue_id="${1:?issue id required}"
  local controller_state=""

  if ! pending_issue_launch_active "${issue_id}"; then
    return 1
  fi

  controller_state="$(resident_issue_controller_state "${issue_id}" || true)"
  if [[ -n "${controller_state}" ]]; then
    case "${controller_state}" in
      idle|sleeping|waiting-due|waiting-open-pr|waiting-provider)
        return 1
        ;;
    esac
  fi

  return 0
}

resident_issue_controller_file() {
  local issue_id="${1:?issue id required}"
  printf '%s/resident-workers/issues/%s/controller.env\n' "${state_root}" "${issue_id}"
}

resident_issue_controller_state() {
  local issue_id="${1:?issue id required}"
  local controller_file state=""

  controller_file="$(resident_issue_controller_file "$issue_id")"
  [[ -f "${controller_file}" ]] || return 1

  state="$(awk -F= '/^CONTROLLER_STATE=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
  [[ -n "${state}" ]] || return 1
  printf '%s\n' "${state}"
}

issue_id_from_session() {
  local session="${1:?session required}"
  local issue_id=""
  if [[ "$session" == "${issue_prefix}"* ]]; then
    issue_id="${session#${issue_prefix}}"
  fi
  if [[ "$issue_id" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$issue_id"
    return 0
  fi
  return 1
}

pr_id_from_session() {
  local session="${1:?session required}"
  local pr_id=""
  if [[ "$session" == "${pr_prefix}"* ]]; then
    pr_id="${session#${pr_prefix}}"
  fi
  if [[ "$pr_id" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$pr_id"
    return 0
  fi
  return 1
}

worker_count() {
  local workers="${1:-}"
  if [[ -z "$workers" ]]; then
    printf '0\n'
    return
  fi
  printf '%s\n' "$workers" | sed '/^$/d' | wc -l | tr -d ' '
}

retry_ready() {
  local kind="${1:?kind required}"
  local item_id="${2:?item id required}"
  local retry_out ready

  retry_out="$(
    "${shared_agent_home}/tools/bin/agent-project-retry-state" \
      --state-root "$state_root" \
      --kind "$kind" \
      --item-id "$item_id" \
      --action get
  )"
  ready="$(awk -F= '/^READY=/{print $2}' <<<"$retry_out")"
  [[ "$ready" == "yes" ]]
}

provider_cooldown_state() {
  "${shared_agent_home}/tools/bin/provider-cooldown-state.sh" get
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

ensure_tmux_sessions_cache() {
  if [[ "$tmux_sessions_cache_loaded" != "yes" ]]; then
    tmux_sessions_cache="$(tmux list-sessions -F '#S' 2>/dev/null || true)"
    tmux_sessions_cache_loaded="yes"
  fi
}

ensure_all_running_workers_cache() {
  local session
  if [[ "$all_running_workers_cache_loaded" == "yes" ]]; then
    return 0
  fi
  ensure_tmux_sessions_cache
  all_running_workers_cache=""
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    if session_matches_prefix "$session"; then
      all_running_workers_cache+="${session}"$'\n'
    fi
  done <<<"$tmux_sessions_cache"
  all_running_workers_cache="${all_running_workers_cache%$'\n'}"
  all_running_workers_cache_loaded="yes"
}

ensure_auth_wait_workers_cache() {
  local session
  if [[ "$auth_wait_workers_cache_loaded" == "yes" ]]; then
    return 0
  fi
  ensure_tmux_sessions_cache
  auth_wait_workers_cache=""
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    session_matches_prefix "$session" || continue
    if session_is_auth_waiting "$session"; then
      auth_wait_workers_cache+="${session}"$'\n'
    fi
  done <<<"$tmux_sessions_cache"
  auth_wait_workers_cache="${auth_wait_workers_cache%$'\n'}"
  auth_wait_workers_cache_loaded="yes"
}

ensure_running_issue_workers_cache() {
  local session
  if [[ "$running_issue_workers_cache_loaded" == "yes" ]]; then
    return 0
  fi
  ensure_tmux_sessions_cache
  running_issue_workers_cache=""
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    if [[ "$session" == "${issue_prefix}"* ]]; then
      if session_is_auth_waiting "$session"; then
        continue
      fi
      running_issue_workers_cache+="${session}"$'\n'
    fi
  done <<<"$tmux_sessions_cache"
  running_issue_workers_cache="${running_issue_workers_cache%$'\n'}"
  running_issue_workers_cache_loaded="yes"
}

ensure_running_pr_workers_cache() {
  local session
  if [[ "$running_pr_workers_cache_loaded" == "yes" ]]; then
    return 0
  fi
  ensure_tmux_sessions_cache
  running_pr_workers_cache=""
  while IFS= read -r session; do
    [[ -n "$session" ]] || continue
    if [[ "$session" == "${pr_prefix}"* ]]; then
      if session_is_auth_waiting "$session"; then
        continue
      fi
      running_pr_workers_cache+="${session}"$'\n'
    fi
  done <<<"$tmux_sessions_cache"
  running_pr_workers_cache="${running_pr_workers_cache%$'\n'}"
  running_pr_workers_cache_loaded="yes"
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
