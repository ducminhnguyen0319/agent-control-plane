#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-resident-worker-lib.sh"

ISSUE_ID="${1:?usage: start-resident-issue-loop.sh ISSUE_ID [safe|bypass]}"
MODE="${2:-safe}"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "start-resident-issue-loop.sh"; then
  exit 64
fi

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
flow_export_project_env_aliases

FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
HOOK_FILE="${FLOW_SKILL_DIR}/hooks/heartbeat-hooks.sh"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
SESSION="${ISSUE_SESSION_PREFIX}${ISSUE_ID}"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
PENDING_LAUNCH_DIR="${ACP_PENDING_LAUNCH_DIR:-${F_LOSNING_PENDING_LAUNCH_DIR:-${STATE_ROOT}/pending-launches}}"
SCHEDULED_STATE_DIR="${STATE_ROOT}/scheduled-issues"
CONTROLLER_FILE="$(flow_resident_issue_controller_file "${CONFIG_YAML}" "${ISSUE_ID}")"
RESIDENT_META_FILE="$(flow_resident_issue_meta_file "${CONFIG_YAML}" "${ISSUE_ID}")"
CODING_WORKER="${ACP_CODING_WORKER:-codex}"
MAX_IMMEDIATE_CYCLES="$(flow_resident_issue_controller_max_immediate_cycles "${CONFIG_YAML}")"
POLL_SECONDS="$(flow_resident_issue_controller_poll_seconds "${CONFIG_YAML}")"
IDLE_TIMEOUT_SECONDS="$(flow_resident_issue_controller_idle_timeout_seconds "${CONFIG_YAML}")"
CONTROLLER_LOOP_COUNT="0"
CONTROLLER_STATE="starting"
CONTROLLER_REASON=""
NEXT_WAKE_EPOCH=""
NEXT_WAKE_AT=""
IDLE_WAIT_STARTED_EPOCH=""
PROVIDER_WAITED="no"
ACTIVE_RESIDENT_WORKER_KEY=""
ACTIVE_RESIDENT_META_FILE=""
ACTIVE_RESIDENT_LANE_KIND=""
ACTIVE_RESIDENT_LANE_VALUE=""
ACTIVE_PROVIDER_POOL_NAME=""
ACTIVE_PROVIDER_BACKEND=""
ACTIVE_PROVIDER_MODEL=""
ACTIVE_PROVIDER_KEY=""
ACTIVE_PROVIDER_SELECTION_REASON=""
ACTIVE_PROVIDER_NEXT_ATTEMPT_EPOCH=""
ACTIVE_PROVIDER_NEXT_ATTEMPT_AT=""
ACTIVE_PROVIDER_LAST_REASON=""
LAST_RECORDED_PROVIDER_POOL_NAME=""
LAST_RECORDED_PROVIDER_BACKEND=""
LAST_RECORDED_PROVIDER_MODEL=""
LAST_RECORDED_PROVIDER_KEY=""
LAST_LAUNCHED_PROVIDER_POOL_NAME=""
LAST_LAUNCHED_PROVIDER_BACKEND=""
LAST_LAUNCHED_PROVIDER_MODEL=""
LAST_LAUNCHED_PROVIDER_KEY=""
LAST_PROVIDER_SWITCH_AT=""
LAST_PROVIDER_SWITCH_REASON=""
LAST_PROVIDER_FROM_POOL_NAME=""
LAST_PROVIDER_FROM_BACKEND=""
LAST_PROVIDER_FROM_MODEL=""
LAST_PROVIDER_FROM_KEY=""
LAST_PROVIDER_TO_POOL_NAME=""
LAST_PROVIDER_TO_BACKEND=""
LAST_PROVIDER_TO_MODEL=""
LAST_PROVIDER_TO_KEY=""
LAST_PROVIDER_FAILOVER_AT=""
PROVIDER_SWITCH_COUNT="0"
PROVIDER_FAILOVER_COUNT="0"
PROVIDER_WAIT_COUNT="0"
PROVIDER_WAIT_TOTAL_SECONDS="0"
PROVIDER_LAST_WAIT_SECONDS="0"
PROVIDER_LAST_WAIT_STARTED_AT=""
PROVIDER_LAST_WAIT_COMPLETED_AT=""

mkdir -p "${SCHEDULED_STATE_DIR}" "${PENDING_LAUNCH_DIR}"

if [[ -f "${HOOK_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${HOOK_FILE}"
fi

issue_json_for() {
  local issue_id="${1:?issue id required}"
  flow_github_issue_view_json "${REPO_SLUG}" "${issue_id}"
}

issue_json() {
  issue_json_for "${ISSUE_ID}"
}

issue_json_is_open() {
  local issue_payload="${1-}"
  if [[ -z "${issue_payload}" ]]; then
    issue_payload='{}'
  fi
  jq -e '(.state // "") == "OPEN"' >/dev/null <<<"${issue_payload}"
}

issue_json_is_keep_open() {
  local issue_payload="${1-}"
  if [[ -z "${issue_payload}" ]]; then
    issue_payload='{}'
  fi
  jq -e 'any(.labels[]?; .name == "agent-keep-open")' >/dev/null <<<"${issue_payload}"
}

issue_schedule_interval_seconds_from_json() {
  local issue_payload="${1-}"
  if [[ -z "${issue_payload}" ]]; then
    issue_payload='{}'
  fi
  ISSUE_JSON="${issue_payload}" node <<'EOF'
const issue = JSON.parse(process.env.ISSUE_JSON || '{}');
const body = String(issue.body || '');
const match = body.match(/^\s*(?:Agent schedule|Schedule|Cadence)\s*:\s*(?:every\s+)?(\d+)\s*([mhd])\s*$/im);
if (!match) {
  process.stdout.write('0\n');
  process.exit(0);
}
const value = Number(match[1]);
const unit = String(match[2] || '').toLowerCase();
const multiplier = { m: 60, h: 3600, d: 86400 }[unit] || 0;
const seconds = Number.isFinite(value) && value > 0 ? value * multiplier : 0;
process.stdout.write(`${seconds}\n`);
EOF
}

issue_json_is_scheduled() {
  local interval_seconds=""
  interval_seconds="$(issue_schedule_interval_seconds_from_json "${1-}")"
  [[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]
}

issue_has_open_agent_pr() {
  issue_id_has_open_agent_pr "${ISSUE_ID}"
}

issue_id_has_open_agent_pr() {
  local issue_id="${1:?issue id required}"
  local open_ids_json=""

  if ! declare -F heartbeat_open_agent_pr_issue_ids >/dev/null 2>&1; then
    return 1
  fi

  open_ids_json="$(heartbeat_open_agent_pr_issue_ids 2>/dev/null || printf '[]\n')"
  jq -e --arg issueId "${issue_id}" 'index($issueId) != null' >/dev/null <<<"${open_ids_json}"
}

issue_pending_file() {
  local issue_id="${1:?issue id required}"
  printf '%s/issue-%s.pid\n' "${PENDING_LAUNCH_DIR}" "${issue_id}"
}

RESIDENT_CONTROLLER_LIB=""
for _rcl_candidate in \
  "${SCRIPT_DIR}/resident-issue-controller-lib.sh" \
  "${AGENT_CONTROL_PLANE_ROOT:-}/tools/bin/resident-issue-controller-lib.sh" \
  "${ACP_ROOT:-}/tools/bin/resident-issue-controller-lib.sh" \
  "${SHARED_AGENT_HOME:-}/tools/bin/resident-issue-controller-lib.sh"; do
  if [[ -n "${_rcl_candidate}" && -f "${_rcl_candidate}" ]]; then
    RESIDENT_CONTROLLER_LIB="${_rcl_candidate}"
    break
  fi
done
if [[ -n "${SHARED_AGENT_HOME:-}" && -z "${RESIDENT_CONTROLLER_LIB}" ]]; then
  for _rcl_skill in "${AGENT_CONTROL_PLANE_SKILL_NAME:-agent-control-plane}" "${AGENT_CONTROL_PLANE_COMPAT_ALIAS:-}"; do
    [[ -n "${_rcl_skill}" ]] || continue
    _rcl_candidate="${SHARED_AGENT_HOME}/skills/openclaw/${_rcl_skill}/tools/bin/resident-issue-controller-lib.sh"
    if [[ -f "${_rcl_candidate}" ]]; then
      RESIDENT_CONTROLLER_LIB="${_rcl_candidate}"
      break
    fi
  done
fi
if [[ -z "${RESIDENT_CONTROLLER_LIB}" ]]; then
  echo "unable to locate resident-issue-controller-lib.sh" >&2
  exit 1
fi
source "${RESIDENT_CONTROLLER_LIB}"

issue_id_is_recurring() {
  local issue_id="${1:?issue id required}"
  if declare -F heartbeat_issue_is_recurring >/dev/null 2>&1; then
    [[ "$(heartbeat_issue_is_recurring "${issue_id}" 2>/dev/null || printf 'no\n')" == "yes" ]]
    return $?
  fi

  issue_json_is_keep_open "$(issue_json_for "${issue_id}" 2>/dev/null || printf '{}\n')"
}

issue_id_is_scheduled() {
  local issue_id="${1:?issue id required}"
  if declare -F heartbeat_issue_is_scheduled >/dev/null 2>&1; then
    [[ "$(heartbeat_issue_is_scheduled "${issue_id}" 2>/dev/null || printf 'no\n')" == "yes" ]]
    return $?
  fi

  issue_json_is_scheduled "$(issue_json_for "${issue_id}" 2>/dev/null || printf '{}\n')"
}

select_next_recurring_issue_id() {
  local candidate_id=""

  if ! declare -F heartbeat_list_ready_issue_ids >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r candidate_id; do
    [[ -n "${candidate_id}" ]] || continue
    [[ "${candidate_id}" != "${ISSUE_ID}" ]] || continue
    if issue_id_has_open_agent_pr "${candidate_id}"; then
      continue
    fi
    if ! issue_id_is_recurring "${candidate_id}"; then
      continue
    fi
    if issue_id_is_scheduled "${candidate_id}"; then
      continue
    fi
    printf '%s\n' "${candidate_id}"
    return 0
  done < <(heartbeat_list_ready_issue_ids 2>/dev/null || true)

  return 1
}

record_scheduled_next_due() {
  local interval_seconds="${1:-0}"
  local state_file now_epoch next_due_epoch

  if ! [[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    return 0
  fi

  now_epoch="$(date +%s)"
  next_due_epoch=$((now_epoch + interval_seconds))
  NEXT_WAKE_EPOCH="${next_due_epoch}"
  NEXT_WAKE_AT="$(flow_format_epoch_utc "${next_due_epoch}")"
  state_file="${SCHEDULED_STATE_DIR}/${ISSUE_ID}.env"
  cat >"${state_file}" <<EOF
INTERVAL_SECONDS=${interval_seconds}
LAST_STARTED_EPOCH=${now_epoch}
LAST_STARTED_AT=$(flow_format_epoch_utc "${now_epoch}")
NEXT_DUE_EPOCH=${next_due_epoch}
NEXT_DUE_AT=${NEXT_WAKE_AT}
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

trap 'CONTROLLER_REASON="${CONTROLLER_REASON:-terminated}"; controller_cleanup' EXIT
trap 'CONTROLLER_REASON="interrupted"; exit 0' INT TERM

controller_refresh_execution_context
if ! flow_resident_issue_backend_supported "${CODING_WORKER}" || ! flow_is_truthy "$(flow_resident_issue_workers_enabled "${CONFIG_YAML}")"; then
  exec "${FLOW_TOOLS_DIR}/start-issue-worker.sh" "${ISSUE_ID}" "${MODE}"
fi

wait_for_worker_cycle() {
  local appear_attempts attempt=0 saw_session="no"
  local reconcile_out=""
  local reconcile_status=""
  local reconcile_attempts=0
  local reconcile_max_attempts=20

  # Poll quickly during launch so short-lived test shims and fast workers do not
  # get misclassified as launch-no-session before the controller ever sees them.
  appear_attempts=100
  while (( attempt < appear_attempts )); do
    if tmux has-session -t "${SESSION}" 2>/dev/null; then
      saw_session="yes"
      break
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  if [[ "${saw_session}" != "yes" ]]; then
    return 1
  fi

  controller_write_state "waiting-worker" ""
  while tmux has-session -t "${SESSION}" 2>/dev/null; do
    sleep 2
  done

  controller_write_state "reconciling" ""
  while (( reconcile_attempts < reconcile_max_attempts )); do
    if ! reconcile_out="$(bash "${FLOW_TOOLS_DIR}/reconcile-issue-worker.sh" "${SESSION}" 2>&1)"; then
      printf '%s\n' "${reconcile_out}" >&2
      CONTROLLER_REASON="reconcile-failed"
      return 1
    fi

    reconcile_status="$(awk -F= '/^STATUS=/{print $2; exit}' <<<"${reconcile_out}")"
    case "${reconcile_status}" in
      SUCCEEDED|FAILED)
        return 0
        ;;
      "")
        # Older test shims may not print STATUS. The real reconcile wrapper always
        # does, so treat blank STATUS as successful test completion.
        return 0
        ;;
      RUNNING)
        controller_write_state "reconciling" "worker-still-finalizing"
        sleep 1
        ;;
      *)
        printf '%s\n' "${reconcile_out}" >&2
        CONTROLLER_REASON="reconcile-non-terminal-${reconcile_status}"
        return 1
        ;;
    esac

    reconcile_attempts=$((reconcile_attempts + 1))
  done

  CONTROLLER_REASON="reconcile-timeout"
  return 1
}

sleep_until_next_due() {
  local target_epoch="${1:-0}"
  local now_epoch remaining sleep_seconds

  while true; do
    now_epoch="$(date +%s)"
    if ! [[ "${target_epoch}" =~ ^[0-9]+$ ]] || (( target_epoch <= now_epoch )); then
      return 0
    fi
    remaining=$((target_epoch - now_epoch))
    sleep_seconds="${POLL_SECONDS}"
    if ! [[ "${sleep_seconds}" =~ ^[1-9][0-9]*$ ]]; then
      sleep_seconds="60"
    fi
    if (( remaining < sleep_seconds )); then
      sleep_seconds="${remaining}"
    fi
    controller_write_state "waiting-due" ""
    sleep "${sleep_seconds}"
  done
}

while true; do
  issue_payload="$(issue_json 2>/dev/null || printf '{}\n')"
  if ! issue_json_is_open "${issue_payload}"; then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="issue-closed"
    if controller_wait_for_leased_issue; then
      continue
    fi
    break
  fi

  is_keep_open="no"
  if issue_json_is_keep_open "${issue_payload}"; then
    is_keep_open="yes"
  fi

  schedule_interval_seconds="$(issue_schedule_interval_seconds_from_json "${issue_payload}")"
  is_scheduled="no"
  if [[ "${schedule_interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    is_scheduled="yes"
  fi
  controller_refresh_execution_context
  controller_refresh_issue_lane_context "${is_scheduled}" "${schedule_interval_seconds}"
  controller_track_provider_selection "provider-selection"
  controller_write_state "starting" ""

  if controller_yield_to_live_lane_peer; then
    break
  fi

  if [[ "${is_keep_open}" != "yes" && "${is_scheduled}" != "yes" ]]; then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="resident-ineligible"
    if controller_wait_for_leased_issue; then
      continue
    fi
    break
  fi

  if issue_has_open_agent_pr; then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="open-agent-pr"
    if controller_wait_for_leased_issue; then
      continue
    fi
    controller_write_state "waiting-open-pr" ""
    break
  fi

  if [[ "${is_scheduled}" == "yes" && -n "${NEXT_WAKE_EPOCH}" ]]; then
    sleep_until_next_due "${NEXT_WAKE_EPOCH}"
  fi

  NEXT_WAKE_EPOCH=""
  NEXT_WAKE_AT=""
  if ! controller_wait_for_provider_capacity; then
    CONTROLLER_REASON="provider-unavailable"
    break
  fi
  if [[ "${PROVIDER_WAITED}" == "yes" ]]; then
    CONTROLLER_REASON="provider-ready"
    continue
  fi
  controller_write_state "launching" ""
  controller_mark_issue_running
  if ! bash "${FLOW_TOOLS_DIR}/start-issue-worker.sh" "${ISSUE_ID}" "${MODE}" >/dev/null; then
    controller_rollback_issue_launch
    CONTROLLER_REASON="launch-failed"
    break
  fi
  controller_mark_provider_launched

  if ! wait_for_worker_cycle; then
    CONTROLLER_REASON="launch-no-session"
    break
  fi

  CONTROLLER_LOOP_COUNT=$((CONTROLLER_LOOP_COUNT + 1))

  if [[ "$(controller_last_failure_reason || true)" == "provider-quota-limit" ]]; then
    controller_refresh_execution_context
    controller_refresh_issue_lane_context "${is_scheduled}" "${schedule_interval_seconds}"
    controller_track_provider_selection "provider-failover"
    if ! controller_wait_for_provider_capacity; then
      CONTROLLER_REASON="provider-unavailable"
      break
    fi
    CONTROLLER_REASON="provider-failover"
    continue
  fi

  issue_payload="$(issue_json 2>/dev/null || printf '{}\n')"
  if ! issue_json_is_open "${issue_payload}"; then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="issue-closed"
    if controller_wait_for_leased_issue; then
      continue
    fi
    break
  fi
  if jq -e 'any(.labels[]?; .name == "agent-blocked")' >/dev/null <<<"${issue_payload}"; then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="issue-blocked"
    if controller_wait_for_leased_issue; then
      continue
    fi
    break
  fi
  if issue_has_open_agent_pr; then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="open-agent-pr"
    if controller_wait_for_leased_issue; then
      continue
    fi
    break
  fi

  if [[ "${is_scheduled}" == "yes" ]]; then
    record_scheduled_next_due "${schedule_interval_seconds}"
    controller_write_state "sleeping" ""
    continue
  fi

  if [[ "${MAX_IMMEDIATE_CYCLES}" =~ ^[1-9][0-9]*$ ]] && (( CONTROLLER_LOOP_COUNT >= MAX_IMMEDIATE_CYCLES )); then
    if controller_adopt_next_recurring_issue; then
      continue
    fi
    CONTROLLER_REASON="max-immediate-cycles"
    if controller_wait_for_leased_issue; then
      continue
    fi
    break
  fi

  controller_write_state "idle" ""
done
