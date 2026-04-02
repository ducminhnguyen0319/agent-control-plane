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
CODING_WORKER="${ACP_CODING_WORKER:-${F_LOSNING_CODING_WORKER:-codex}}"
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

controller_unregister_pending_issue() {
  local issue_id="${1:-${ISSUE_ID:-}}"
  [[ -n "${issue_id}" ]] || return 0
  rm -f "$(issue_pending_file "${issue_id}")"
}

controller_register_pending_issue() {
  [[ -n "${ISSUE_ID:-}" ]] || return 0
  printf '%s\n' "$$" >"$(issue_pending_file "${ISSUE_ID}")"
}

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

controller_refresh_execution_context() {
  unset \
    ACP_CODING_WORKER F_LOSNING_CODING_WORKER \
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
  CODING_WORKER="${ACP_CODING_WORKER:-${F_LOSNING_CODING_WORKER:-codex}}"
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
      -u ACP_CODING_WORKER -u F_LOSNING_CODING_WORKER \
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
          PROVIDER_LAST_WAIT_COMPLETED_AT="$(date -u -r "${wait_completed_epoch}" +"%Y-%m-%dT%H:%M:%SZ")"
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
      PROVIDER_LAST_WAIT_STARTED_AT="$(date -u -r "${wait_started_epoch}" +"%Y-%m-%dT%H:%M:%SZ")"
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

record_scheduled_next_due() {
  local interval_seconds="${1:-0}"
  local state_file now_epoch next_due_epoch

  if ! [[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    return 0
  fi

  now_epoch="$(date +%s)"
  next_due_epoch=$((now_epoch + interval_seconds))
  NEXT_WAKE_EPOCH="${next_due_epoch}"
  NEXT_WAKE_AT="$(date -u -r "${next_due_epoch}" +"%Y-%m-%dT%H:%M:%SZ")"
  state_file="${SCHEDULED_STATE_DIR}/${ISSUE_ID}.env"
  cat >"${state_file}" <<EOF
INTERVAL_SECONDS=${interval_seconds}
LAST_STARTED_EPOCH=${now_epoch}
LAST_STARTED_AT=$(date -u -r "${now_epoch}" +"%Y-%m-%dT%H:%M:%SZ")
NEXT_DUE_EPOCH=${next_due_epoch}
NEXT_DUE_AT=${NEXT_WAKE_AT}
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

controller_cleanup() {
  controller_write_state "stopped" "${CONTROLLER_REASON:-stopped}"
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
