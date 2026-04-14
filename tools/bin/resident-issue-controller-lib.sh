#!/usr/bin/env bash
# resident-issue-controller-lib.sh — controller_* functions for the resident
# issue loop.  Sourced by start-resident-issue-loop.sh to keep the main script
# focused on the top-level loop logic.

controller_unregister_pending_issue() {
  local issue_id="${1:-${ISSUE_ID:-}}"
  [[ -n "${issue_id}" ]] || return 0
  rm -f "$(issue_pending_file "${issue_id}")"
}

controller_register_pending_issue() {
  [[ -n "${ISSUE_ID:-}" ]] || return 0
  printf '%s\n' "$$" >"$(issue_pending_file "${ISSUE_ID}")"
}

controller_refresh_execution_context() {
  unset \
    ACP_CODING_WORKER \
    ACP_CODEX_PROFILE_SAFE F_LOSNING_CODEX_PROFILE_SAFE \
    ACP_CODEX_PROFILE_BYPASS F_LOSNING_CODEX_PROFILE_BYPASS \
    ACP_CLAUDE_MODEL F_LOSNING_CLAUDE_MODEL \
    ACP_CLAUDE_PERMISSION_MODE F_LOSNING_CLAUDE_PERMISSION_MODE \
    ACP_CLAUDE_EFFORT F_LOSNING_CLAUDE_EFFORT \
    ACP_CLAUDE_TIMEOUT_SECONDS F_LOSNING_CLAUDE_TIMEOUT_SECONDS \
    ACP_CLAUDE_MAX_ATTEMPTS F_LOSNING_CLAUDE_MAX_ATTEMPTS \
    ACP_CLAUDE_RETRY_BACKOFF_SECONDS F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS \
    ACP_OPENCLAW_MODEL F_LOSNING_OPENCLAW_MODEL \
    ACP_OPENCLAW_THINKING F_LOSNING_OPENCLAW_THINKING \
    ACP_OPENCLAW_TIMEOUT_SECONDS F_LOSNING_OPENCLAW_TIMEOUT_SECONDS \
    ACP_OPENCLAW_STALL_SECONDS F_LOSNING_OPENCLAW_STALL_SECONDS \
    ACP_ACTIVE_PROVIDER_POOL_NAME F_LOSNING_ACTIVE_PROVIDER_POOL_NAME \
    ACP_ACTIVE_PROVIDER_BACKEND F_LOSNING_ACTIVE_PROVIDER_BACKEND \
    ACP_ACTIVE_PROVIDER_MODEL F_LOSNING_ACTIVE_PROVIDER_MODEL \
    ACP_ACTIVE_PROVIDER_KEY F_LOSNING_ACTIVE_PROVIDER_KEY \
    ACP_PROVIDER_POOLS_EXHAUSTED F_LOSNING_PROVIDER_POOLS_EXHAUSTED \
    ACP_PROVIDER_POOL_SELECTION_REASON F_LOSNING_PROVIDER_POOL_SELECTION_REASON \
    ACP_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH \
    ACP_PROVIDER_POOL_NEXT_ATTEMPT_AT F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_AT \
    ACP_PROVIDER_POOL_LAST_REASON F_LOSNING_PROVIDER_POOL_LAST_REASON
  flow_export_execution_env "${CONFIG_YAML}"
  flow_export_project_env_aliases
  CODING_WORKER="${ACP_CODING_WORKER:-codex}"
  controller_capture_active_provider_context
}

controller_refresh_issue_lane_context() {
  local is_scheduled="${1:-no}"
  local schedule_interval_seconds="${2:-0}"

  if [[ "${is_scheduled}" == "yes" ]]; then
    ACTIVE_RESIDENT_LANE_KIND="scheduled"
    ACTIVE_RESIDENT_LANE_VALUE="${schedule_interval_seconds}"
  else
    ACTIVE_RESIDENT_LANE_KIND="recurring"
    ACTIVE_RESIDENT_LANE_VALUE="general"
  fi

  ACTIVE_RESIDENT_WORKER_KEY="$(flow_resident_issue_lane_key "${CODING_WORKER}" "${MODE}" "${ACTIVE_RESIDENT_LANE_KIND}" "${ACTIVE_RESIDENT_LANE_VALUE}")"
  ACTIVE_RESIDENT_META_FILE="$(flow_resident_issue_lane_meta_file "${CONFIG_YAML}" "${ACTIVE_RESIDENT_WORKER_KEY}")"
}

controller_live_lane_peer() {
  [[ -n "${ACTIVE_RESIDENT_WORKER_KEY}" ]] || return 1
  flow_resident_live_issue_controller_for_key "${CONFIG_YAML}" "${ACTIVE_RESIDENT_WORKER_KEY}" "$$" || return 1
}

controller_yield_to_live_lane_peer() {
  local live_controller=""
  local controller_issue_id=""
  local controller_state=""

  live_controller="$(controller_live_lane_peer || true)"
  [[ -n "${live_controller}" ]] || return 1

  controller_issue_id="$(awk -F= '/^ISSUE_ID=/{print $2; exit}' <<<"${live_controller}")"
  controller_state="$(awk -F= '/^CONTROLLER_STATE=/{print $2; exit}' <<<"${live_controller}")"

  if [[ -n "${controller_issue_id}" && "${controller_issue_id}" != "${ISSUE_ID}" ]]; then
    flow_resident_issue_enqueue "${CONFIG_YAML}" "${ISSUE_ID}" "resident-live-lane" >/dev/null || true
    CONTROLLER_REASON="live-lane-controller-${controller_issue_id}-${controller_state:-running}"
  else
    CONTROLLER_REASON="duplicate-live-lane-controller"
  fi

  return 0
}

controller_capture_active_provider_context() {
  ACTIVE_PROVIDER_POOL_NAME="${ACP_ACTIVE_PROVIDER_POOL_NAME:-${F_LOSNING_ACTIVE_PROVIDER_POOL_NAME:-}}"
  ACTIVE_PROVIDER_BACKEND="${ACP_ACTIVE_PROVIDER_BACKEND:-${F_LOSNING_ACTIVE_PROVIDER_BACKEND:-${CODING_WORKER:-}}}"
  ACTIVE_PROVIDER_MODEL="${ACP_ACTIVE_PROVIDER_MODEL:-${F_LOSNING_ACTIVE_PROVIDER_MODEL:-}}"
  ACTIVE_PROVIDER_KEY="${ACP_ACTIVE_PROVIDER_KEY:-${F_LOSNING_ACTIVE_PROVIDER_KEY:-}}"
  ACTIVE_PROVIDER_SELECTION_REASON="${ACP_PROVIDER_POOL_SELECTION_REASON:-${F_LOSNING_PROVIDER_POOL_SELECTION_REASON:-}}"
  ACTIVE_PROVIDER_NEXT_ATTEMPT_EPOCH="${ACP_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH:-${F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH:-}}"
  ACTIVE_PROVIDER_NEXT_ATTEMPT_AT="${ACP_PROVIDER_POOL_NEXT_ATTEMPT_AT:-${F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_AT:-}}"
  ACTIVE_PROVIDER_LAST_REASON="${ACP_PROVIDER_POOL_LAST_REASON:-${F_LOSNING_PROVIDER_POOL_LAST_REASON:-}}"

  if [[ -z "${ACTIVE_PROVIDER_MODEL}" ]]; then
    case "${ACTIVE_PROVIDER_BACKEND}" in
      openclaw)
        ACTIVE_PROVIDER_MODEL="${ACP_OPENCLAW_MODEL:-${F_LOSNING_OPENCLAW_MODEL:-}}"
        ;;
      claude)
        ACTIVE_PROVIDER_MODEL="${ACP_CLAUDE_MODEL:-${F_LOSNING_CLAUDE_MODEL:-}}"
        ;;
      codex)
        ACTIVE_PROVIDER_MODEL="${ACP_CODEX_PROFILE_SAFE:-${F_LOSNING_CODEX_PROFILE_SAFE:-}}"
        ;;
      opencode)
        ACTIVE_PROVIDER_MODEL="${ACP_OPENCODE_MODEL:-${F_LOSNING_OPENCODE_MODEL:-}}"
        ;;
      kilo)
        ACTIVE_PROVIDER_MODEL="${ACP_KILO_MODEL:-${F_LOSNING_KILO_MODEL:-}}"
        ;;
    esac
  fi

  if [[ -z "${ACTIVE_PROVIDER_KEY}" && -n "${ACTIVE_PROVIDER_BACKEND}" && -n "${ACTIVE_PROVIDER_MODEL}" ]]; then
    ACTIVE_PROVIDER_KEY="$(flow_sanitize_provider_key "${ACTIVE_PROVIDER_BACKEND}-${ACTIVE_PROVIDER_MODEL}")"
  fi
}

controller_set_recorded_provider_from_active() {
  LAST_RECORDED_PROVIDER_POOL_NAME="${ACTIVE_PROVIDER_POOL_NAME}"
  LAST_RECORDED_PROVIDER_BACKEND="${ACTIVE_PROVIDER_BACKEND}"
  LAST_RECORDED_PROVIDER_MODEL="${ACTIVE_PROVIDER_MODEL}"
  LAST_RECORDED_PROVIDER_KEY="${ACTIVE_PROVIDER_KEY}"
}

controller_mark_provider_launched() {
  LAST_LAUNCHED_PROVIDER_POOL_NAME="${ACTIVE_PROVIDER_POOL_NAME}"
  LAST_LAUNCHED_PROVIDER_BACKEND="${ACTIVE_PROVIDER_BACKEND}"
  LAST_LAUNCHED_PROVIDER_MODEL="${ACTIVE_PROVIDER_MODEL}"
  LAST_LAUNCHED_PROVIDER_KEY="${ACTIVE_PROVIDER_KEY}"

  if [[ -z "${LAST_RECORDED_PROVIDER_KEY}" ]]; then
    controller_set_recorded_provider_from_active
  fi
}

controller_track_provider_selection() {
  local reason="${1:-provider-selection}"
  local now_at=""

  [[ -n "${ACTIVE_PROVIDER_KEY}" ]] || return 0

  if [[ -z "${LAST_RECORDED_PROVIDER_KEY}" ]]; then
    controller_set_recorded_provider_from_active
    return 0
  fi

  if [[ "${ACTIVE_PROVIDER_KEY}" == "${LAST_RECORDED_PROVIDER_KEY}" ]]; then
    return 0
  fi

  now_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  PROVIDER_SWITCH_COUNT=$((PROVIDER_SWITCH_COUNT + 1))
  LAST_PROVIDER_SWITCH_AT="${now_at}"
  LAST_PROVIDER_SWITCH_REASON="${reason}"
  LAST_PROVIDER_FROM_POOL_NAME="${LAST_RECORDED_PROVIDER_POOL_NAME}"
  LAST_PROVIDER_FROM_BACKEND="${LAST_RECORDED_PROVIDER_BACKEND}"
  LAST_PROVIDER_FROM_MODEL="${LAST_RECORDED_PROVIDER_MODEL}"
  LAST_PROVIDER_FROM_KEY="${LAST_RECORDED_PROVIDER_KEY}"
  LAST_PROVIDER_TO_POOL_NAME="${ACTIVE_PROVIDER_POOL_NAME}"
  LAST_PROVIDER_TO_BACKEND="${ACTIVE_PROVIDER_BACKEND}"
  LAST_PROVIDER_TO_MODEL="${ACTIVE_PROVIDER_MODEL}"
  LAST_PROVIDER_TO_KEY="${ACTIVE_PROVIDER_KEY}"

  if [[ "${reason}" == "provider-failover" ]]; then
    PROVIDER_FAILOVER_COUNT=$((PROVIDER_FAILOVER_COUNT + 1))
    LAST_PROVIDER_FAILOVER_AT="${now_at}"
  fi

  controller_set_recorded_provider_from_active
}

controller_adopt_issue() {
  local next_issue_id="${1:?issue id required}"
  local previous_issue_id="${ISSUE_ID:-}"
  local previous_controller_file="${CONTROLLER_FILE:-}"

  if [[ -n "${previous_issue_id}" && "${previous_issue_id}" != "${next_issue_id}" ]]; then
    controller_unregister_pending_issue "${previous_issue_id}"
    if [[ -n "${previous_controller_file}" && -f "${previous_controller_file}" ]]; then
      rm -f "${previous_controller_file}"
    fi
  fi

  ISSUE_ID="${next_issue_id}"
  SESSION="${ISSUE_SESSION_PREFIX}${ISSUE_ID}"
  CONTROLLER_FILE="$(flow_resident_issue_controller_file "${CONFIG_YAML}" "${ISSUE_ID}")"
  RESIDENT_META_FILE="$(flow_resident_issue_meta_file "${CONFIG_YAML}" "${ISSUE_ID}")"
  CONTROLLER_LOOP_COUNT="0"
  NEXT_WAKE_EPOCH=""
  NEXT_WAKE_AT=""
  IDLE_WAIT_STARTED_EPOCH=""
  ACTIVE_RESIDENT_WORKER_KEY=""
  ACTIVE_RESIDENT_META_FILE=""
  ACTIVE_RESIDENT_LANE_KIND=""
  ACTIVE_RESIDENT_LANE_VALUE=""
}

controller_mark_issue_running() {
  local is_heavy="no"

  if declare -F heartbeat_issue_is_heavy >/dev/null 2>&1; then
    is_heavy="$(heartbeat_issue_is_heavy "${ISSUE_ID}" 2>/dev/null || printf 'no\n')"
  fi

  if declare -F heartbeat_mark_issue_running >/dev/null 2>&1; then
    heartbeat_mark_issue_running "${ISSUE_ID}" "${is_heavy}" >/dev/null 2>&1 || true
  fi
}

controller_rollback_issue_launch() {
  if declare -F heartbeat_issue_launch_failed >/dev/null 2>&1; then
    heartbeat_issue_launch_failed "${ISSUE_ID}" >/dev/null 2>&1 || true
  fi
}

controller_adopt_next_recurring_issue() {
  local next_issue_id=""
  local claim_out=""
  local claim_file=""

  claim_out="$(flow_resident_issue_claim_next "${CONFIG_YAML}" "${SESSION}" "${ISSUE_ID}" || true)"
  next_issue_id="$(awk -F= '/^ISSUE_ID=/{print $2}' <<<"${claim_out}")"
  claim_file="$(awk -F= '/^CLAIM_FILE=/{print $2}' <<<"${claim_out}")"
  if [[ -z "${next_issue_id}" ]]; then
    next_issue_id="$(select_next_recurring_issue_id || true)"
  fi
  [[ -n "${next_issue_id}" ]] || return 1

  controller_adopt_issue "${next_issue_id}"
  flow_resident_issue_release_claim "${claim_file}"
  CONTROLLER_REASON="adopted-next-recurring-issue"
  controller_write_state "adopting-issue" ""
  return 0
}

controller_wait_for_leased_issue() {
  local idle_timeout="${IDLE_TIMEOUT_SECONDS:-0}"
  local now_epoch=""

  case "${idle_timeout}" in
    ''|*[!0-9]*) idle_timeout="0" ;;
  esac

  if [[ "${idle_timeout}" -le 0 ]]; then
    return 1
  fi

  if [[ -z "${IDLE_WAIT_STARTED_EPOCH}" ]]; then
    IDLE_WAIT_STARTED_EPOCH="$(date +%s)"
  fi

  while true; do
    if controller_adopt_next_recurring_issue; then
      return 0
    fi

    now_epoch="$(date +%s)"
    if (( now_epoch - IDLE_WAIT_STARTED_EPOCH >= idle_timeout )); then
      CONTROLLER_REASON="idle-timeout"
      return 1
    fi

    controller_write_state "idle" ""
    sleep "${POLL_SECONDS}"
  done
}

controller_write_state() {
  local state="${1:?state required}"
  local reason="${2:-${CONTROLLER_REASON}}"

  CONTROLLER_STATE="${state}"
  CONTROLLER_REASON="${reason}"
  flow_resident_write_metadata "${CONTROLLER_FILE}" \
    "ISSUE_ID=${ISSUE_ID}" \
    "SESSION=${SESSION}" \
    "CONTROLLER_PID=$$" \
    "CONTROLLER_MODE=${MODE}" \
    "CONTROLLER_LOOP_COUNT=${CONTROLLER_LOOP_COUNT}" \
    "CONTROLLER_STATE=${CONTROLLER_STATE}" \
    "CONTROLLER_REASON=${CONTROLLER_REASON}" \
    "ACTIVE_RESIDENT_WORKER_KEY=${ACTIVE_RESIDENT_WORKER_KEY}" \
    "ACTIVE_RESIDENT_LANE_KIND=${ACTIVE_RESIDENT_LANE_KIND}" \
    "ACTIVE_RESIDENT_LANE_VALUE=${ACTIVE_RESIDENT_LANE_VALUE}" \
    "ACTIVE_PROVIDER_POOL_NAME=${ACTIVE_PROVIDER_POOL_NAME}" \
    "ACTIVE_PROVIDER_BACKEND=${ACTIVE_PROVIDER_BACKEND}" \
    "ACTIVE_PROVIDER_MODEL=${ACTIVE_PROVIDER_MODEL}" \
    "ACTIVE_PROVIDER_KEY=${ACTIVE_PROVIDER_KEY}" \
    "ACTIVE_PROVIDER_SELECTION_REASON=${ACTIVE_PROVIDER_SELECTION_REASON}" \
    "ACTIVE_PROVIDER_NEXT_ATTEMPT_EPOCH=${ACTIVE_PROVIDER_NEXT_ATTEMPT_EPOCH}" \
    "ACTIVE_PROVIDER_NEXT_ATTEMPT_AT=${ACTIVE_PROVIDER_NEXT_ATTEMPT_AT}" \
    "ACTIVE_PROVIDER_LAST_REASON=${ACTIVE_PROVIDER_LAST_REASON}" \
    "LAST_LAUNCHED_PROVIDER_POOL_NAME=${LAST_LAUNCHED_PROVIDER_POOL_NAME}" \
    "LAST_LAUNCHED_PROVIDER_BACKEND=${LAST_LAUNCHED_PROVIDER_BACKEND}" \
    "LAST_LAUNCHED_PROVIDER_MODEL=${LAST_LAUNCHED_PROVIDER_MODEL}" \
    "LAST_LAUNCHED_PROVIDER_KEY=${LAST_LAUNCHED_PROVIDER_KEY}" \
    "PROVIDER_SWITCH_COUNT=${PROVIDER_SWITCH_COUNT}" \
    "PROVIDER_FAILOVER_COUNT=${PROVIDER_FAILOVER_COUNT}" \
    "LAST_PROVIDER_SWITCH_AT=${LAST_PROVIDER_SWITCH_AT}" \
    "LAST_PROVIDER_SWITCH_REASON=${LAST_PROVIDER_SWITCH_REASON}" \
    "LAST_PROVIDER_FROM_POOL_NAME=${LAST_PROVIDER_FROM_POOL_NAME}" \
    "LAST_PROVIDER_FROM_BACKEND=${LAST_PROVIDER_FROM_BACKEND}" \
    "LAST_PROVIDER_FROM_MODEL=${LAST_PROVIDER_FROM_MODEL}" \
    "LAST_PROVIDER_FROM_KEY=${LAST_PROVIDER_FROM_KEY}" \
    "LAST_PROVIDER_TO_POOL_NAME=${LAST_PROVIDER_TO_POOL_NAME}" \
    "LAST_PROVIDER_TO_BACKEND=${LAST_PROVIDER_TO_BACKEND}" \
    "LAST_PROVIDER_TO_MODEL=${LAST_PROVIDER_TO_MODEL}" \
    "LAST_PROVIDER_TO_KEY=${LAST_PROVIDER_TO_KEY}" \
    "LAST_PROVIDER_FAILOVER_AT=${LAST_PROVIDER_FAILOVER_AT}" \
    "PROVIDER_WAIT_COUNT=${PROVIDER_WAIT_COUNT}" \
    "PROVIDER_WAIT_TOTAL_SECONDS=${PROVIDER_WAIT_TOTAL_SECONDS}" \
    "PROVIDER_LAST_WAIT_SECONDS=${PROVIDER_LAST_WAIT_SECONDS}" \
    "PROVIDER_LAST_WAIT_STARTED_AT=${PROVIDER_LAST_WAIT_STARTED_AT}" \
    "PROVIDER_LAST_WAIT_COMPLETED_AT=${PROVIDER_LAST_WAIT_COMPLETED_AT}" \
    "NEXT_WAKE_EPOCH=${NEXT_WAKE_EPOCH}" \
    "NEXT_WAKE_AT=${NEXT_WAKE_AT}" \
    "UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ "${CONTROLLER_STATE}" == "stopped" ]]; then
    controller_unregister_pending_issue "${ISSUE_ID}"
  elif flow_resident_issue_controller_counts_as_pending "${CONTROLLER_STATE}"; then
    controller_register_pending_issue
  else
    controller_unregister_pending_issue "${ISSUE_ID}"
  fi
}

controller_last_failure_reason() {
  local metadata_file="${ACTIVE_RESIDENT_META_FILE:-${RESIDENT_META_FILE:-}}"
  [[ -n "${metadata_file}" && -f "${metadata_file}" ]] || return 1
  awk -F= '/^LAST_FAILURE_REASON=/{print $2; exit}' "${metadata_file}" 2>/dev/null | tr -d '"' || true
}

controller_provider_state() {
  local provider_state_script="${FLOW_TOOLS_DIR}/provider-cooldown-state.sh"
  local provider_state=""

  if [[ ! -x "${provider_state_script}" ]]; then
    printf 'READY=yes\n'
    return 0
  fi

  provider_state="$(
    env \
      -u ACP_CODING_WORKER \
      -u ACP_CODEX_PROFILE_SAFE -u F_LOSNING_CODEX_PROFILE_SAFE \
      -u ACP_CODEX_PROFILE_BYPASS -u F_LOSNING_CODEX_PROFILE_BYPASS \
      -u ACP_CLAUDE_MODEL -u F_LOSNING_CLAUDE_MODEL \
      -u ACP_CLAUDE_PERMISSION_MODE -u F_LOSNING_CLAUDE_PERMISSION_MODE \
      -u ACP_CLAUDE_EFFORT -u F_LOSNING_CLAUDE_EFFORT \
      -u ACP_CLAUDE_TIMEOUT_SECONDS -u F_LOSNING_CLAUDE_TIMEOUT_SECONDS \
      -u ACP_CLAUDE_MAX_ATTEMPTS -u F_LOSNING_CLAUDE_MAX_ATTEMPTS \
      -u ACP_CLAUDE_RETRY_BACKOFF_SECONDS -u F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS \
      -u ACP_OPENCLAW_MODEL -u F_LOSNING_OPENCLAW_MODEL \
      -u ACP_OPENCLAW_THINKING -u F_LOSNING_OPENCLAW_THINKING \
      -u ACP_OPENCLAW_TIMEOUT_SECONDS -u F_LOSNING_OPENCLAW_TIMEOUT_SECONDS \
      -u ACP_ACTIVE_PROVIDER_POOL_NAME -u F_LOSNING_ACTIVE_PROVIDER_POOL_NAME \
      -u ACP_ACTIVE_PROVIDER_BACKEND -u F_LOSNING_ACTIVE_PROVIDER_BACKEND \
      -u ACP_ACTIVE_PROVIDER_MODEL -u F_LOSNING_ACTIVE_PROVIDER_MODEL \
      -u ACP_ACTIVE_PROVIDER_KEY -u F_LOSNING_ACTIVE_PROVIDER_KEY \
      -u ACP_PROVIDER_POOLS_EXHAUSTED -u F_LOSNING_PROVIDER_POOLS_EXHAUSTED \
      -u ACP_PROVIDER_POOL_SELECTION_REASON -u F_LOSNING_PROVIDER_POOL_SELECTION_REASON \
      -u ACP_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH -u F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH \
      -u ACP_PROVIDER_POOL_NEXT_ATTEMPT_AT -u F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_AT \
      -u ACP_PROVIDER_POOL_LAST_REASON -u F_LOSNING_PROVIDER_POOL_LAST_REASON \
      "${provider_state_script}" get 2>/dev/null || true
  )"
  if [[ -z "${provider_state}" ]]; then
    printf 'READY=yes\n'
    return 0
  fi

  printf '%s\n' "${provider_state}"
}

controller_wait_for_provider_capacity() {
  local provider_state=""
  local provider_ready=""
  local provider_next_epoch=""
  local provider_next_at=""
  local now_epoch=""
  local remaining=""
  local sleep_seconds=""
  local wait_started_epoch=""
  local wait_completed_epoch=""

  PROVIDER_WAITED="no"

  while true; do
    provider_state="$(controller_provider_state)"
    provider_ready="$(flow_kv_get "${provider_state}" "READY")"
    if [[ "${provider_ready}" == "yes" ]]; then
      if [[ -n "${wait_started_epoch}" ]]; then
        wait_completed_epoch="$(date +%s)"
        if (( wait_completed_epoch >= wait_started_epoch )); then
          PROVIDER_LAST_WAIT_SECONDS=$((wait_completed_epoch - wait_started_epoch))
          PROVIDER_WAIT_TOTAL_SECONDS=$((PROVIDER_WAIT_TOTAL_SECONDS + PROVIDER_LAST_WAIT_SECONDS))
          PROVIDER_LAST_WAIT_COMPLETED_AT="$(flow_format_epoch_utc "${wait_completed_epoch}")"
        fi
      fi
      NEXT_WAKE_EPOCH=""
      NEXT_WAKE_AT=""
      return 0
    fi

    provider_next_epoch="$(flow_kv_get "${provider_state}" "NEXT_ATTEMPT_EPOCH")"
    provider_next_at="$(flow_kv_get "${provider_state}" "NEXT_ATTEMPT_AT")"
    if ! [[ "${provider_next_epoch}" =~ ^[0-9]+$ ]] || [[ "${provider_next_epoch}" == "0" ]]; then
      return 1
    fi

    if [[ -z "${wait_started_epoch}" ]]; then
      wait_started_epoch="$(date +%s)"
      PROVIDER_WAIT_COUNT=$((PROVIDER_WAIT_COUNT + 1))
      PROVIDER_LAST_WAIT_STARTED_AT="$(flow_format_epoch_utc "${wait_started_epoch}")"
    fi

    PROVIDER_WAITED="yes"
    NEXT_WAKE_EPOCH="${provider_next_epoch}"
    NEXT_WAKE_AT="${provider_next_at}"
    CONTROLLER_REASON="provider-cooldown"
    controller_write_state "waiting-provider" ""

    now_epoch="$(date +%s)"
    remaining=$((provider_next_epoch - now_epoch))
    sleep_seconds="${POLL_SECONDS}"
    if ! [[ "${sleep_seconds}" =~ ^[1-9][0-9]*$ ]]; then
      sleep_seconds="60"
    fi
    if (( remaining > 0 && remaining < sleep_seconds )); then
      sleep_seconds="${remaining}"
    fi
    if (( sleep_seconds <= 0 )); then
      sleep_seconds="1"
    fi
    sleep "${sleep_seconds}"
  done
}

controller_cleanup() {
  controller_write_state "stopped" "${CONTROLLER_REASON:-stopped}"
}
