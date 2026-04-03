#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

flow_is_truthy() {
  local value="${1:-}"
  case "${value}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

flow_resident_issue_workers_enabled() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_env_or_config \
    "${config_file}" \
    "ACP_RESIDENT_ISSUE_WORKERS_ENABLED F_LOSNING_RESIDENT_ISSUE_WORKERS_ENABLED" \
    "execution.resident_workers.issue_reuse_enabled" \
    "1"
}

flow_resident_issue_worker_max_tasks() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_env_or_config \
    "${config_file}" \
    "ACP_RESIDENT_ISSUE_WORKER_MAX_TASKS F_LOSNING_RESIDENT_ISSUE_WORKER_MAX_TASKS" \
    "execution.resident_workers.issue_max_tasks_per_worker" \
    "12"
}

flow_resident_issue_worker_max_age_seconds() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_env_or_config \
    "${config_file}" \
    "ACP_RESIDENT_ISSUE_WORKER_MAX_AGE_SECONDS F_LOSNING_RESIDENT_ISSUE_WORKER_MAX_AGE_SECONDS" \
    "execution.resident_workers.issue_max_age_seconds" \
    "86400"
}

flow_resident_issue_controller_max_immediate_cycles() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_env_or_config \
    "${config_file}" \
    "ACP_RESIDENT_ISSUE_CONTROLLER_MAX_IMMEDIATE_CYCLES F_LOSNING_RESIDENT_ISSUE_CONTROLLER_MAX_IMMEDIATE_CYCLES" \
    "execution.resident_workers.issue_controller_max_immediate_cycles" \
    "2"
}

flow_resident_issue_controller_poll_seconds() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_env_or_config \
    "${config_file}" \
    "ACP_RESIDENT_ISSUE_CONTROLLER_POLL_SECONDS F_LOSNING_RESIDENT_ISSUE_CONTROLLER_POLL_SECONDS" \
    "execution.resident_workers.controller_poll_seconds" \
    "60"
}

flow_resident_issue_controller_idle_timeout_seconds() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_env_or_config \
    "${config_file}" \
    "ACP_RESIDENT_ISSUE_CONTROLLER_IDLE_TIMEOUT_SECONDS F_LOSNING_RESIDENT_ISSUE_CONTROLLER_IDLE_TIMEOUT_SECONDS" \
    "execution.resident_workers.issue_controller_idle_timeout_seconds" \
    "600"
}

flow_resident_issue_controller_counts_as_pending() {
  local state="${1:-}"

  case "${state}" in
    idle|sleeping|waiting-due|waiting-open-pr|waiting-provider)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

flow_resident_issue_backend_supported() {
  local backend="${1:-}"

  case "${backend}" in
    codex|openclaw|claude|ollama)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

flow_resident_workers_root() {
  local config_file="${1:-}"
  local state_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  state_root="$(flow_resolve_state_root "${config_file}")"
  printf '%s/resident-workers\n' "${state_root}"
}

flow_resident_issue_key() {
  local issue_id="${1:?issue id required}"
  printf 'issue-%s\n' "${issue_id}"
}

flow_resident_issue_lane_key() {
  local backend="${1:-openclaw}"
  local mode="${2:-safe}"
  local lane_kind="${3:-recurring}"
  local lane_value="${4:-general}"

  printf '%s\n' "$(flow_resident_sanitize_id "issue-lane-${lane_kind}-${lane_value}-${backend}-${mode}")"
}

flow_resident_issue_lane_field_from_key() {
  local lane_key="${1:-}"
  local field="${2:?field required}"
  local suffix=""
  local lane_payload=""
  local lane_kind=""
  local lane_value=""
  local backend=""
  local mode=""

  [[ -n "${lane_key}" ]] || return 1
  [[ "${lane_key}" == issue-lane-* ]] || return 1

  for backend in codex openclaw claude; do
    for mode in safe bypass; do
      suffix="-${backend}-${mode}"
      [[ "${lane_key}" == *"${suffix}" ]] || continue
      lane_payload="${lane_key#issue-lane-}"
      lane_payload="${lane_payload%"${suffix}"}"
      lane_kind="${lane_payload%%-*}"
      lane_value="${lane_payload#${lane_kind}-}"
      [[ -n "${lane_kind}" ]] || return 1
      [[ "${lane_value}" != "${lane_payload}" ]] || return 1

      case "${field}" in
        kind)
          printf '%s\n' "${lane_kind}"
          return 0
          ;;
        value)
          printf '%s\n' "${lane_value}"
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    done
  done

  return 1
}

flow_resident_issue_dir() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"
  local resident_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  resident_root="$(flow_resident_workers_root "${config_file}")"
  printf '%s/issues/%s\n' "${resident_root}" "${issue_id}"
}

flow_resident_issue_lane_dir() {
  local config_file="${1:-}"
  local lane_key="${2:?lane key required}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s\n' "$(flow_resident_issue_dir "${config_file}" "${lane_key}")"
}

flow_resident_issue_meta_file() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s/metadata.env\n' "$(flow_resident_issue_dir "${config_file}" "${issue_id}")"
}

flow_resident_issue_lane_meta_file() {
  local config_file="${1:-}"
  local lane_key="${2:?lane key required}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s/metadata.env\n' "$(flow_resident_issue_lane_dir "${config_file}" "${lane_key}")"
}

flow_resident_issue_queue_root() {
  local config_file="${1:-}"
  local resident_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  resident_root="$(flow_resident_workers_root "${config_file}")"
  printf '%s/issue-queue\n' "${resident_root}"
}

flow_resident_issue_queue_pending_dir() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s/pending\n' "$(flow_resident_issue_queue_root "${config_file}")"
}

flow_resident_issue_queue_claims_dir() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s/claims\n' "$(flow_resident_issue_queue_root "${config_file}")"
}

flow_resident_issue_queue_file() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s/issue-%s.env\n' "$(flow_resident_issue_queue_pending_dir "${config_file}")" "${issue_id}"
}

flow_resident_issue_controller_file() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  printf '%s/controller.env\n' "$(flow_resident_issue_dir "${config_file}" "${issue_id}")"
}

flow_resident_issue_queue_count() {
  local config_file="${1:-}"
  local pending_dir=""
  local queue_file=""
  local count=0

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  pending_dir="$(flow_resident_issue_queue_pending_dir "${config_file}")"
  for queue_file in "${pending_dir}"/issue-*.env; do
    [[ -f "${queue_file}" ]] || continue
    count=$((count + 1))
  done

  printf '%s\n' "${count}"
}

flow_resident_issue_enqueue() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"
  local queued_by="${3:-heartbeat}"
  local pending_dir=""
  local claims_dir=""
  local queue_file=""
  local tmp_file=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  pending_dir="$(flow_resident_issue_queue_pending_dir "${config_file}")"
  claims_dir="$(flow_resident_issue_queue_claims_dir "${config_file}")"
  queue_file="$(flow_resident_issue_queue_file "${config_file}" "${issue_id}")"

  mkdir -p "${pending_dir}" "${claims_dir}"

  if [[ -f "${queue_file}" ]] || compgen -G "${claims_dir}/issue-${issue_id}.*" >/dev/null; then
    printf 'QUEUE_STATUS=exists\n'
    printf 'ISSUE_ID=%s\n' "${issue_id}"
    return 0
  fi

  tmp_file="${queue_file}.tmp.$$"
  flow_resident_write_metadata "${tmp_file}" \
    "ISSUE_ID=${issue_id}" \
    "QUEUED_BY=${queued_by}" \
    "QUEUED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mv "${tmp_file}" "${queue_file}"

  printf 'QUEUE_STATUS=enqueued\n'
  printf 'ISSUE_ID=%s\n' "${issue_id}"
}

flow_resident_issue_claim_next() {
  local config_file="${1:-}"
  local claimer_key="${2:-resident-controller}"
  local skip_issue_id="${3:-}"
  local pending_dir=""
  local claims_dir=""
  local queue_file=""
  local issue_id=""
  local claim_file=""
  local claim_key=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  pending_dir="$(flow_resident_issue_queue_pending_dir "${config_file}")"
  claims_dir="$(flow_resident_issue_queue_claims_dir "${config_file}")"
  claim_key="$(flow_resident_sanitize_id "${claimer_key}")"
  mkdir -p "${pending_dir}" "${claims_dir}"

  for queue_file in "${pending_dir}"/issue-*.env; do
    [[ -f "${queue_file}" ]] || continue
    issue_id="${queue_file##*/issue-}"
    issue_id="${issue_id%.env}"
    [[ -n "${issue_id}" ]] || continue
    [[ "${issue_id}" != "${skip_issue_id}" ]] || continue

    claim_file="${claims_dir}/issue-${issue_id}.${claim_key}.$$"
    if mv "${queue_file}" "${claim_file}" 2>/dev/null; then
      printf 'ISSUE_ID=%s\n' "${issue_id}"
      printf 'CLAIM_FILE=%s\n' "${claim_file}"
      return 0
    fi
  done

  return 1
}

flow_resident_issue_release_claim() {
  local claim_file="${1:-}"
  [[ -n "${claim_file}" ]] || return 0
  rm -f "${claim_file}"
}

flow_resident_controller_pid_live() {
  local pid="${1:-}"
  local expected_substring="${2:-start-resident-issue-loop.sh}"
  local command=""

  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1

  if [[ -n "${expected_substring}" ]]; then
    command="$(ps -p "${pid}" -o command= 2>/dev/null | sed 's/^ *//' || true)"
    [[ -n "${command}" && "${command}" == *"${expected_substring}"* ]] || return 1
  fi

  return 0
}

flow_resident_issue_controller_reap_file() {
  local config_file="${1:-}"
  local controller_file="${2:?controller file required}"
  local state_root=""
  local issue_id=""
  local controller_pid=""
  local controller_state=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  [[ -f "${controller_file}" ]] || return 1

  issue_id="$(awk -F= '/^ISSUE_ID=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
  controller_pid="$(awk -F= '/^CONTROLLER_PID=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
  controller_state="$(awk -F= '/^CONTROLLER_STATE=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"

  if [[ "${controller_state}" != "stopped" ]] && flow_resident_controller_pid_live "${controller_pid}"; then
    return 1
  fi

  state_root="$(flow_resolve_state_root "${config_file}")"
  if [[ -n "${issue_id}" ]]; then
    rm -f "${state_root}/pending-launches/issue-${issue_id}.pid"
  fi
  rm -f "${controller_file}"
  return 0
}

flow_resident_issue_reap_stale_state() {
  local config_file="${1:-}"
  local resident_root=""
  local controller_file=""
  local reaped="0"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  resident_root="$(flow_resident_workers_root "${config_file}")"
  for controller_file in "${resident_root}"/issues/*/controller.env; do
    [[ -f "${controller_file}" ]] || continue
    if flow_resident_issue_controller_reap_file "${config_file}" "${controller_file}"; then
      reaped=$((reaped + 1))
    fi
  done

  printf '%s\n' "${reaped}"
}

flow_resident_live_issue_controller_for_key() {
  local config_file="${1:-}"
  local worker_key="${2:?worker key required}"
  local exclude_pid="${3:-}"
  local resident_root=""
  local controller_file=""
  local controller_pid=""
  local controller_state=""
  local controller_worker_key=""
  local controller_issue_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  resident_root="$(flow_resident_workers_root "${config_file}")"

  for controller_file in "${resident_root}"/issues/*/controller.env; do
    [[ -f "${controller_file}" ]] || continue
    controller_pid="$(awk -F= '/^CONTROLLER_PID=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
    [[ "${controller_pid}" =~ ^[0-9]+$ ]] || continue
    [[ -n "${exclude_pid}" && "${controller_pid}" == "${exclude_pid}" ]] && continue
    if ! flow_resident_controller_pid_live "${controller_pid}"; then
      flow_resident_issue_controller_reap_file "${config_file}" "${controller_file}" >/dev/null 2>&1 || true
      continue
    fi

    controller_state="$(awk -F= '/^CONTROLLER_STATE=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
    if [[ "${controller_state}" == "stopped" ]]; then
      flow_resident_issue_controller_reap_file "${config_file}" "${controller_file}" >/dev/null 2>&1 || true
      continue
    fi

    controller_worker_key="$(awk -F= '/^ACTIVE_RESIDENT_WORKER_KEY=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
    [[ -n "${controller_worker_key}" && "${controller_worker_key}" == "${worker_key}" ]] || continue

    controller_issue_id="$(awk -F= '/^ISSUE_ID=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
    printf 'ISSUE_ID=%s\n' "${controller_issue_id}"
    printf 'CONTROLLER_PID=%s\n' "${controller_pid}"
    printf 'CONTROLLER_STATE=%s\n' "${controller_state}"
    printf 'CONTROLLER_FILE=%s\n' "${controller_file}"
    return 0
  done

  return 1
}

flow_resident_sanitize_id() {
  local raw_id="${1:?raw id required}"

  printf '%s' "${raw_id}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
    | cut -c1-63
}

flow_resident_issue_openclaw_agent_id() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  flow_resident_sanitize_id "${adapter_id}-resident-issue-${issue_id}"
}

flow_resident_issue_lane_openclaw_agent_id() {
  local config_file="${1:-}"
  local lane_key="${2:?lane key required}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  flow_resident_sanitize_id "${adapter_id}-resident-${lane_key}"
}

flow_resident_issue_openclaw_session_id() {
  local config_file="${1:-}"
  local issue_id="${2:?issue id required}"
  local task_count="${3:-}"
  local adapter_id=""
  local base_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  base_id="${adapter_id}-resident-session-issue-${issue_id}"
  if [[ -n "${task_count}" ]]; then
    base_id="${base_id}-cycle-${task_count}"
  fi
  flow_resident_sanitize_id "${base_id}"
}

flow_resident_issue_lane_openclaw_session_id() {
  local config_file="${1:-}"
  local lane_key="${2:?lane key required}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  flow_resident_sanitize_id "${adapter_id}-resident-session-${lane_key}"
}

flow_resident_write_metadata() {
  local metadata_file="${1:?metadata file required}"
  local tmp_file=""
  local entry=""
  local key=""
  local value=""
  shift

  mkdir -p "$(dirname "${metadata_file}")"
  tmp_file="${metadata_file}.tmp.$$"

  : >"${tmp_file}"
  for entry in "$@"; do
    [[ -n "${entry}" ]] || continue
    key="${entry%%=*}"
    value="${entry#*=}"
    printf '%s=%q\n' "${key}" "${value}" >>"${tmp_file}"
  done

  mv "${tmp_file}" "${metadata_file}"
}

flow_resident_metadata_value() {
  local metadata_file="${1:?metadata file required}"
  local key="${2:?metadata key required}"

  [[ -f "${metadata_file}" ]] || return 1

  (
    set -a
    # shellcheck source=/dev/null
    source "${metadata_file}"
    set +a
    printf '%s\n' "${!key:-}"
  )
}

flow_iso8601_to_epoch() {
  local iso_value="${1:-}"

  [[ -n "${iso_value}" ]] || return 1

  python3 - "${iso_value}" <<'PY'
import sys
from datetime import datetime, timezone

value = sys.argv[1].strip()
if not value:
    raise SystemExit(1)

try:
    dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
except ValueError:
    raise SystemExit(1)

print(int(dt.timestamp()))
PY
}

flow_resident_issue_worktree_is_usable() {
  local worktree="${1:-}"
  local worktree_realpath="${2:-}"
  local resolved_worktree=""
  local resolved_realpath=""

  [[ -n "${worktree}" && -d "${worktree}" ]] || return 1
  [[ -e "${worktree}/.git" ]] || return 1

  if [[ -n "${worktree_realpath}" ]]; then
    [[ -d "${worktree_realpath}" && -e "${worktree_realpath}/.git" ]] || return 1
    resolved_worktree="$(cd "${worktree}" 2>/dev/null && pwd -P || true)"
    resolved_realpath="$(cd "${worktree_realpath}" 2>/dev/null && pwd -P || true)"
    [[ -n "${resolved_worktree}" && -n "${resolved_realpath}" ]] || return 1
    [[ "${resolved_worktree}" == "${resolved_realpath}" ]] || return 1
  fi

  return 0
}

flow_resident_issue_can_reuse() {
  local metadata_file="${1:?metadata file required}"
  local max_tasks="${2:-0}"
  local max_age_seconds="${3:-0}"

  [[ -f "${metadata_file}" ]] || return 1

  (
    local task_count="0"
    local reference_time=""
    local reference_epoch=""
    local now_epoch=""
    local age_seconds=""

    set -a
    # shellcheck source=/dev/null
    source "${metadata_file}"
    set +a

    flow_resident_issue_worktree_is_usable "${WORKTREE:-}" "${WORKTREE_REALPATH:-}" || exit 1

    task_count="${TASK_COUNT:-0}"
    case "${task_count}" in
      ''|*[!0-9]*) task_count="0" ;;
    esac

    case "${max_tasks}" in
      ''|*[!0-9]*) max_tasks="0" ;;
    esac
    if [[ "${max_tasks}" -gt 0 && "${task_count}" -ge "${max_tasks}" ]]; then
      exit 1
    fi

    case "${max_age_seconds}" in
      ''|*[!0-9]*) max_age_seconds="0" ;;
    esac
    if [[ "${max_age_seconds}" -gt 0 ]]; then
      reference_time="${LAST_FINISHED_AT:-${LAST_STARTED_AT:-}}"
      reference_epoch="$(flow_iso8601_to_epoch "${reference_time}" 2>/dev/null || true)"
      if [[ -z "${reference_epoch}" ]]; then
        exit 1
      fi
      now_epoch="$(date +%s)"
      age_seconds=$((now_epoch - reference_epoch))
      if [[ "${age_seconds}" -gt "${max_age_seconds}" ]]; then
        exit 1
      fi
    fi

    exit 0
  )
}
