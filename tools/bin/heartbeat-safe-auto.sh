#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"
flow_export_project_env_aliases

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "heartbeat-safe-auto.sh"; then
  exit 64
fi

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
MEMORY_DIR="${ACP_MEMORY_DIR:-${F_LOSNING_MEMORY_DIR:-${AGENT_CONTROL_PLANE_WORKSPACE:-$HOME/.agent-runtime/control-plane/workspace}/memory}}"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
MAX_CONCURRENT_WORKERS="${ACP_MAX_CONCURRENT_WORKERS:-${F_LOSNING_MAX_CONCURRENT_WORKERS:-20}}"
MAX_CONCURRENT_E2E_WORKERS="${ACP_MAX_CONCURRENT_E2E_WORKERS:-${F_LOSNING_MAX_CONCURRENT_E2E_WORKERS:-1}}"
MAX_CONCURRENT_PR_WORKERS="${ACP_MAX_CONCURRENT_PR_WORKERS:-${F_LOSNING_MAX_CONCURRENT_PR_WORKERS:-12}}"
MAX_RECURRING_ISSUE_WORKERS="${ACP_MAX_RECURRING_ISSUE_WORKERS:-${F_LOSNING_MAX_RECURRING_ISSUE_WORKERS:-6}}"
MAX_CONCURRENT_SCHEDULED_ISSUE_WORKERS="${ACP_MAX_CONCURRENT_SCHEDULED_ISSUE_WORKERS:-${F_LOSNING_MAX_CONCURRENT_SCHEDULED_ISSUE_WORKERS:-2}}"
MAX_CONCURRENT_SCHEDULED_HEAVY_WORKERS="${ACP_MAX_CONCURRENT_SCHEDULED_HEAVY_WORKERS:-${F_LOSNING_MAX_CONCURRENT_SCHEDULED_HEAVY_WORKERS:-1}}"
MAX_CONCURRENT_BLOCKED_RECOVERY_ISSUE_WORKERS="${ACP_MAX_CONCURRENT_BLOCKED_RECOVERY_ISSUE_WORKERS:-${F_LOSNING_MAX_CONCURRENT_BLOCKED_RECOVERY_ISSUE_WORKERS:-1}}"
BLOCKED_RECOVERY_COOLDOWN_SECONDS="${ACP_BLOCKED_RECOVERY_COOLDOWN_SECONDS:-${F_LOSNING_BLOCKED_RECOVERY_COOLDOWN_SECONDS:-900}}"
MAX_OPEN_AGENT_PRS_FOR_RECURRING="${ACP_MAX_OPEN_AGENT_PRS_FOR_RECURRING:-${F_LOSNING_MAX_OPEN_AGENT_PRS_FOR_RECURRING:-12}}"
MAX_LAUNCHES_PER_HEARTBEAT="${ACP_MAX_LAUNCHES_PER_HEARTBEAT:-${F_LOSNING_MAX_LAUNCHES_PER_HEARTBEAT:-$MAX_CONCURRENT_WORKERS}}"
CODING_WORKER="${ACP_CODING_WORKER:-codex}"
# The catchup and shared heartbeat passes can legitimately take a few minutes
# once they reconcile stale sessions, sync labels, and launch multiple workers.
CATCHUP_TIMEOUT_SECONDS="${ACP_CATCHUP_TIMEOUT_SECONDS:-${F_LOSNING_CATCHUP_TIMEOUT_SECONDS:-180}}"
HEARTBEAT_LOOP_TIMEOUT_SECONDS="${ACP_HEARTBEAT_LOOP_TIMEOUT_SECONDS:-${F_LOSNING_HEARTBEAT_LOOP_TIMEOUT_SECONDS:-720}}"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
SHARED_AGENT_HOME="$(resolve_shared_agent_home "${FLOW_SKILL_DIR}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
PR_SESSION_PREFIX="$(flow_resolve_pr_session_prefix "${CONFIG_YAML}")"
HOOK_FILE="${FLOW_SKILL_DIR}/hooks/heartbeat-hooks.sh"
RECOVERY_PREFLIGHT_SCRIPT="${FLOW_TOOLS_DIR}/heartbeat-recovery-preflight.sh"
HEARTBEAT_PREFLIGHT_ONLY="${ACP_HEARTBEAT_PREFLIGHT_ONLY:-${F_LOSNING_HEARTBEAT_PREFLIGHT_ONLY:-0}}"
CODEX_QUOTA_AUTOSWITCH_ENABLED="${ACP_CODEX_QUOTA_AUTOSWITCH_ENABLED:-${F_LOSNING_CODEX_QUOTA_AUTOSWITCH_ENABLED:-1}}"
CODEX_QUOTA_ROTATION_STRATEGY="${ACP_CODEX_QUOTA_ROTATION_STRATEGY:-${F_LOSNING_CODEX_QUOTA_ROTATION_STRATEGY:-failure-driven}}"
CODEX_QUOTA_THRESHOLD="${ACP_CODEX_QUOTA_THRESHOLD:-${F_LOSNING_CODEX_QUOTA_THRESHOLD:-70}}"
CODEX_QUOTA_WEEKLY_THRESHOLD="${ACP_CODEX_QUOTA_WEEKLY_THRESHOLD:-${F_LOSNING_CODEX_QUOTA_WEEKLY_THRESHOLD:-90}}"
CODEX_QUOTA_SOFT_THRESHOLD="${ACP_CODEX_QUOTA_SOFT_THRESHOLD:-${F_LOSNING_CODEX_QUOTA_SOFT_THRESHOLD:-55}}"
CODEX_QUOTA_SOFT_WORKER_THRESHOLD="${ACP_CODEX_QUOTA_SOFT_WORKER_THRESHOLD:-${F_LOSNING_CODEX_QUOTA_SOFT_WORKER_THRESHOLD:-8}}"
CODEX_QUOTA_EMERGENCY_THRESHOLD="${ACP_CODEX_QUOTA_EMERGENCY_THRESHOLD:-${F_LOSNING_CODEX_QUOTA_EMERGENCY_THRESHOLD:-65}}"
CODEX_QUOTA_EMERGENCY_WORKER_THRESHOLD="${ACP_CODEX_QUOTA_EMERGENCY_WORKER_THRESHOLD:-${F_LOSNING_CODEX_QUOTA_EMERGENCY_WORKER_THRESHOLD:-12}}"
CODEX_QUOTA_SWITCH_COOLDOWN_SECONDS="${ACP_CODEX_QUOTA_SWITCH_COOLDOWN_SECONDS:-${F_LOSNING_CODEX_QUOTA_SWITCH_COOLDOWN_SECONDS:-600}}"
CODEX_QUOTA_TIMEOUT_SECONDS="${ACP_CODEX_QUOTA_TIMEOUT_SECONDS:-${F_LOSNING_CODEX_QUOTA_TIMEOUT_SECONDS:-45}}"
CODEX_QUOTA_PREFER_LABEL="${ACP_CODEX_QUOTA_PREFER_LABEL:-${F_LOSNING_CODEX_QUOTA_PREFER_LABEL:-}}"
CODEX_QUOTA_BIN="$(flow_resolve_codex_quota_bin "${FLOW_SKILL_DIR}")"
CODEX_QUOTA_MANAGER_SCRIPT="$(flow_resolve_codex_quota_manager_script "${FLOW_SKILL_DIR}")"
CODEX_QUOTA_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-quota-manager"
CODEX_QUOTA_FULL_CACHE_FILE="${CODEX_QUOTA_MANAGER_FULL_CACHE_FILE:-${CODEX_QUOTA_CACHE_DIR}/codex-full-quota.json}"
CODEX_QUOTA_CACHE_MAX_AGE_SECONDS="${CODEX_QUOTA_CACHE_MAX_AGE_SECONDS:-${ACP_CODEX_QUOTA_CACHE_MAX_AGE_SECONDS:-${F_LOSNING_CODEX_QUOTA_CACHE_MAX_AGE_SECONDS:-900}}}"
DYNAMIC_CONCURRENCY_ENABLED="${ACP_DYNAMIC_CONCURRENCY_ENABLED:-${F_LOSNING_DYNAMIC_CONCURRENCY_ENABLED:-1}}"
ALLOW_INFRA_CI_BYPASS="${ACP_ALLOW_INFRA_CI_BYPASS:-${F_LOSNING_ALLOW_INFRA_CI_BYPASS:-1}}"
RETAINED_WORKTREE_AUDIT_ENABLED="${ACP_RETAINED_WORKTREE_AUDIT_ENABLED:-${F_LOSNING_RETAINED_WORKTREE_AUDIT_ENABLED:-1}}"
RETAINED_WORKTREE_AUDIT_TIMEOUT_SECONDS="${ACP_RETAINED_WORKTREE_AUDIT_TIMEOUT_SECONDS:-${F_LOSNING_RETAINED_WORKTREE_AUDIT_TIMEOUT_SECONDS:-30}}"
AGENT_WORKTREE_AUDIT_ENABLED="${ACP_AGENT_WORKTREE_AUDIT_ENABLED:-${F_LOSNING_AGENT_WORKTREE_AUDIT_ENABLED:-1}}"
AGENT_WORKTREE_AUDIT_TIMEOUT_SECONDS="${ACP_AGENT_WORKTREE_AUDIT_TIMEOUT_SECONDS:-${F_LOSNING_AGENT_WORKTREE_AUDIT_TIMEOUT_SECONDS:-45}}"
LOCK_DIR="${STATE_ROOT}/heartbeat-loop.lock"
PID_FILE="${LOCK_DIR}/pid"
SHARED_LOOP_PID_FILE="${STATE_ROOT}/shared-heartbeat-loop.pid"
SHARED_LOOP_STATUS_FILE="${STATE_ROOT}/shared-heartbeat-loop.env"
QUOTA_LOCK_DIR="${STATE_ROOT}/quota-preflight.lock"
QUOTA_PID_FILE="${QUOTA_LOCK_DIR}/pid"

mkdir -p "${AGENT_ROOT}" "${RUNS_ROOT}" "${STATE_ROOT}" "${HISTORY_ROOT}" "${WORKTREE_ROOT}" "${MEMORY_DIR}"

acquire_lock() {
  mkdir -p "${STATE_ROOT}"

  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" >"${PID_FILE}"
    return 0
  fi

  if [[ -f "${PID_FILE}" ]]; then
    local existing_pid
    existing_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
      printf 'HEARTBEAT_SKIPPED=lock-held\n'
      printf 'LOCK_PID=%s\n' "${existing_pid}"
      exit 0
    fi
  fi

  rm -rf "${LOCK_DIR}"
  mkdir "${LOCK_DIR}"
  printf '%s\n' "$$" >"${PID_FILE}"
}

cleanup() {
  rm -rf "${LOCK_DIR}"
}

acquire_quota_lock() {
  mkdir -p "${STATE_ROOT}"

  if mkdir "${QUOTA_LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" >"${QUOTA_PID_FILE}"
    return 0
  fi

  if [[ -f "${QUOTA_PID_FILE}" ]]; then
    local existing_pid
    existing_pid="$(cat "${QUOTA_PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
      printf '[%s] codex quota preflight skipped lock-held pid=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${existing_pid}"
      return 1
    fi
  fi

  rm -rf "${QUOTA_LOCK_DIR}"
  mkdir "${QUOTA_LOCK_DIR}"
  printf '%s\n' "$$" >"${QUOTA_PID_FILE}"
  return 0
}

release_quota_lock() {
  rm -rf "${QUOTA_LOCK_DIR}"
}

write_shared_loop_status() {
  local state="${1:-}"
  local status="${2:-}"
  local timestamp=""
  local tmp_file=""

  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "${STATE_ROOT}"
  tmp_file="$(mktemp)"
  if [[ -f "${SHARED_LOOP_STATUS_FILE}" ]]; then
    grep -Ev '^(STATE|STATUS|STARTED_AT|UPDATED_AT)=' "${SHARED_LOOP_STATUS_FILE}" >"${tmp_file}" || true
  fi
  printf 'STATE=%s\n' "${state}" >>"${tmp_file}"
  if [[ -n "${status}" ]]; then
    printf 'STATUS=%s\n' "${status}" >>"${tmp_file}"
  fi
  if [[ "${state}" == "running" ]]; then
    printf 'STARTED_AT=%s\n' "${timestamp}" >>"${tmp_file}"
  fi
  printf 'UPDATED_AT=%s\n' "${timestamp}" >>"${tmp_file}"
  mv "${tmp_file}" "${SHARED_LOOP_STATUS_FILE}"
}

run_with_timeout() {
  local timeout_seconds="${1:?timeout seconds required}"
  shift

  /opt/homebrew/bin/python3 - "${timeout_seconds}" "$@" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
argv = sys.argv[2:]
pid_file = os.environ.get("ACP_TIMEOUT_CHILD_PID_FILE") or os.environ.get("F_LOSNING_TIMEOUT_CHILD_PID_FILE", "")

if not argv:
    sys.exit(64)

proc = subprocess.Popen(argv, start_new_session=True)
if pid_file:
    Path(pid_file).write_text(f"{proc.pid}\n", encoding="utf-8")

try:
    sys.exit(proc.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()

    sys.exit(124)
finally:
    if pid_file:
        try:
            Path(pid_file).unlink()
        except FileNotFoundError:
            pass
PY
}

active_shared_loop_pid() {
  if [[ ! -f "${SHARED_LOOP_PID_FILE}" ]]; then
    return 1
  fi

  local pid parent_pid command
  pid="$(tr -d '[:space:]' <"${SHARED_LOOP_PID_FILE}" 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    rm -f "${SHARED_LOOP_PID_FILE}"
    return 1
  fi

  if kill -0 "${pid}" 2>/dev/null; then
    command="$(ps -p "${pid}" -o command= 2>/dev/null | sed 's/^ *//' || true)"
    if [[ -z "${command}" || "${command}" != *"agent-project-heartbeat-loop --repo-slug ${REPO_SLUG}"* ]]; then
      rm -f "${SHARED_LOOP_PID_FILE}"
      return 1
    fi
    parent_pid="$(ps -p "${pid}" -o ppid= 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "${parent_pid}" == "1" ]]; then
      kill -TERM -- "-${pid}" 2>/dev/null || true
      sleep 1
      kill -KILL -- "-${pid}" 2>/dev/null || true
      rm -f "${SHARED_LOOP_PID_FILE}"
      return 1
    fi
    printf '%s\n' "${pid}"
    return 0
  fi

  rm -f "${SHARED_LOOP_PID_FILE}"
  return 1
}

reap_orphan_shared_loop_groups() {
  local ps_lines root_pid root_pgid
  ps_lines="$(
    ps -Ao pid=,ppid=,pgid=,command= 2>/dev/null \
      | awk '/agent-project-heartbeat-loop/ {print $1 "|" $2 "|" $3 "|" $0}'
  )"

  while IFS='|' read -r root_pid parent_pid root_pgid _; do
    [[ -n "${root_pid}" ]] || continue
    [[ "${parent_pid}" == "1" ]] || continue
    [[ -n "${root_pgid}" ]] || continue
    kill -TERM -- "-${root_pgid}" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-${root_pgid}" 2>/dev/null || true
  done <<<"${ps_lines}"
}

codex_quota_health_reason() {
  if [[ "${CODEX_QUOTA_AUTOSWITCH_ENABLED}" == "0" ]]; then
    printf 'disabled\n'
    return 0
  fi
  if [[ ! -x "${CODEX_QUOTA_MANAGER_SCRIPT}" ]]; then
    printf 'missing-script\n'
    return 0
  fi
  if [[ ! -x "${CODEX_QUOTA_BIN}" ]]; then
    printf 'missing-codex-quota\n'
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'missing-jq\n'
    return 0
  fi
  printf 'ok\n'
}

run_codex_quota_preflight() {
  if [[ "${CODING_WORKER}" != "codex" ]]; then
    printf 'CODING_WORKER=%s\n' "${CODING_WORKER}"
    printf 'CODEX_QUOTA_PREFLIGHT_SKIPPED_FOR_WORKER=yes\n'
    return 0
  fi

  local unavailable_reason=""
  unavailable_reason="$(codex_quota_health_reason)"
  if [[ "${unavailable_reason}" != "ok" ]]; then
    printf 'CODEX_QUOTA_MANAGER_UNAVAILABLE=yes\n'
    printf 'CODEX_QUOTA_MANAGER_REASON=%s\n' "${unavailable_reason}"
    printf '[%s] codex quota preflight skipped unavailable (%s)\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${unavailable_reason}"
  fi

  if [[ "${CODEX_QUOTA_AUTOSWITCH_ENABLED}" == "0" ]]; then
    printf 'CODEX_QUOTA_AUTOSWITCH_ENABLED=0\n'
    return 0
  fi

  printf 'CODEX_QUOTA_ROTATION_STRATEGY=%s\n' "${CODEX_QUOTA_ROTATION_STRATEGY}"
  printf 'CODEX_QUOTA_PREFLIGHT_SKIPPED=strategy-%s\n' "${CODEX_QUOTA_ROTATION_STRATEGY}"
  printf '[%s] codex quota preflight skipped strategy=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${CODEX_QUOTA_ROTATION_STRATEGY}"
  return 0
}

derive_dynamic_limits() {
EFFECTIVE_MAX_CONCURRENT_WORKERS="${MAX_CONCURRENT_WORKERS}"
EFFECTIVE_MAX_CONCURRENT_PR_WORKERS="${MAX_CONCURRENT_PR_WORKERS}"
EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS="${MAX_RECURRING_ISSUE_WORKERS}"
EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT="${MAX_LAUNCHES_PER_HEARTBEAT}"
HEALTHY_QUOTA_POOLS=""
ROTATION_QUOTA_POOLS=""
EFFECTIVE_QUOTA_POOLS=""

  if [[ "${CODING_WORKER}" != "codex" ]]; then
    printf 'CODING_WORKER=%s\n' "${CODING_WORKER}"
    printf 'DYNAMIC_CONCURRENCY_QUOTA_MODE=non-codex-bypass\n'
    printf 'EFFECTIVE_MAX_CONCURRENT_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_WORKERS}"
    printf 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_PR_WORKERS}"
    printf 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=%s\n' "${EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS}"
    printf 'EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT=%s\n' "${EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT}"
    return 0
  fi

  if [[ "${DYNAMIC_CONCURRENCY_ENABLED}" == "0" ]]; then
    printf 'DYNAMIC_CONCURRENCY_ENABLED=0\n'
    printf 'EFFECTIVE_MAX_CONCURRENT_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_WORKERS}"
    printf 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_PR_WORKERS}"
    printf 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=%s\n' "${EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS}"
    printf 'EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT=%s\n' "${EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT}"
    return 0
  fi

  printf 'CODEX_QUOTA_ROTATION_STRATEGY=%s\n' "${CODEX_QUOTA_ROTATION_STRATEGY}"

  local quota_cache_age_seconds=""
  quota_cache_age_seconds="$(
    /opt/homebrew/bin/python3 - "${CODEX_QUOTA_FULL_CACHE_FILE}" <<'PY' 2>/dev/null || true
import os
import sys
import time

path = sys.argv[1]
try:
    stat = os.stat(path)
except OSError:
    sys.exit(1)

age = max(0, int(time.time() - stat.st_mtime))
print(age)
PY
  )"

  if [[ ! -f "${CODEX_QUOTA_FULL_CACHE_FILE}" || ! -s "${CODEX_QUOTA_FULL_CACHE_FILE}" ]] || ! command -v jq >/dev/null 2>&1; then
    printf 'DYNAMIC_CONCURRENCY_QUOTA_MODE=failure-driven-static\n'
    printf 'EFFECTIVE_MAX_CONCURRENT_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_WORKERS}"
    printf 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_PR_WORKERS}"
    printf 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=%s\n' "${EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS}"
    printf 'EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT=%s\n' "${EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT}"
    return 0
  fi

  if [[ "${CODEX_QUOTA_CACHE_MAX_AGE_SECONDS}" =~ ^[0-9]+$ ]] \
    && [[ "${quota_cache_age_seconds:-}" =~ ^[0-9]+$ ]] \
    && (( quota_cache_age_seconds > CODEX_QUOTA_CACHE_MAX_AGE_SECONDS )); then
    printf 'DYNAMIC_CONCURRENCY_QUOTA_MODE=failure-driven-static\n'
    printf 'DYNAMIC_CONCURRENCY_QUOTA_CACHE_STALE=yes\n'
    printf 'DYNAMIC_CONCURRENCY_QUOTA_CACHE_AGE_SECONDS=%s\n' "${quota_cache_age_seconds}"
    printf 'EFFECTIVE_MAX_CONCURRENT_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_WORKERS}"
    printf 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_PR_WORKERS}"
    printf 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=%s\n' "${EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS}"
    printf 'EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT=%s\n' "${EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT}"
    return 0
  fi

  local healthy_pools=""
  local rotation_pools=""
  local effective_pools=""
  healthy_pools="$(
    jq -r --argjson primaryThresh "${CODEX_QUOTA_THRESHOLD}" --argjson weeklyThresh "${CODEX_QUOTA_WEEKLY_THRESHOLD}" '
      map(. + {poolKey: (.label // .trackedLabel // .email // .accountId // "")})
      | map(select(
          (.poolKey != "")
          and ((.usage.rate_limit.limit_reached // false) | not)
          and ((.usage.rate_limit.primary_window.used_percent // 100) < $primaryThresh)
          and ((.usage.rate_limit.secondary_window.used_percent // 100) < $weeklyThresh)
        ) | .poolKey)
      | unique
      | length
    ' "${CODEX_QUOTA_FULL_CACHE_FILE}" 2>/dev/null || true
  )"

  rotation_pools="$(
    jq -r --argjson weeklyThresh "${CODEX_QUOTA_WEEKLY_THRESHOLD}" '
      map(. + {poolKey: (.label // .trackedLabel // .email // .accountId // "")})
      | map(select(
          (.poolKey != "")
          and ((.usage.rate_limit.limit_reached // false) | not)
          and ((.usage.rate_limit.secondary_window.used_percent // 100) < $weeklyThresh)
          and ((.planType // "") != "free")
        ) | .poolKey)
      | unique
      | length
    ' "${CODEX_QUOTA_FULL_CACHE_FILE}" 2>/dev/null || true
  )"

  if ! [[ "${healthy_pools:-}" =~ ^[0-9]+$ ]]; then
    printf 'DYNAMIC_CONCURRENCY_QUOTA_MODE=failure-driven-static\n'
    printf 'EFFECTIVE_MAX_CONCURRENT_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_WORKERS}"
    printf 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_PR_WORKERS}"
    printf 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=%s\n' "${EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS}"
    printf 'EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT=%s\n' "${EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT}"
    return 0
  fi
  if ! [[ "${rotation_pools:-}" =~ ^[0-9]+$ ]]; then
    rotation_pools="${healthy_pools}"
  fi

  # Healthy pools are immediately usable under the current 5h/weekly thresholds.
  # Rotation pools include accounts that are still viable on weekly budget but may
  # already be warm on the 5h window. Count the extra capacity at half weight so
  # the scheduler burns harder without assuming every warm pool is instantly safe.
  effective_pools="${healthy_pools}"
  if (( rotation_pools > healthy_pools )); then
    effective_pools=$((healthy_pools + ((rotation_pools - healthy_pools) / 2)))
  fi

  local target_workers target_pr_workers target_recurring_workers
  if (( effective_pools <= 0 )); then
    target_workers=0
    target_pr_workers=0
    target_recurring_workers=0
  elif (( effective_pools >= 12 )); then
    target_workers=18
    target_pr_workers=10
    target_recurring_workers=5
  elif (( effective_pools >= 10 )); then
    target_workers=16
    target_pr_workers=9
    target_recurring_workers=5
  elif (( effective_pools >= 8 )); then
    target_workers=14
    target_pr_workers=8
    target_recurring_workers=4
  elif (( effective_pools >= 6 )); then
    target_workers=12
    target_pr_workers=7
    target_recurring_workers=4
  elif (( effective_pools >= 4 )); then
    target_workers=10
    target_pr_workers=6
    target_recurring_workers=3
  elif (( effective_pools >= 3 )); then
    target_workers=8
    target_pr_workers=4
    target_recurring_workers=3
  else
    target_workers=6
    target_pr_workers=3
    target_recurring_workers=2
  fi

  if (( target_workers > MAX_CONCURRENT_WORKERS )); then
    target_workers="${MAX_CONCURRENT_WORKERS}"
  fi
  if (( target_pr_workers > MAX_CONCURRENT_PR_WORKERS )); then
    target_pr_workers="${MAX_CONCURRENT_PR_WORKERS}"
  fi
  if (( target_pr_workers > target_workers )); then
    target_pr_workers="${target_workers}"
  fi
  if (( target_recurring_workers > MAX_RECURRING_ISSUE_WORKERS )); then
    target_recurring_workers="${MAX_RECURRING_ISSUE_WORKERS}"
  fi
  if (( target_recurring_workers > target_workers )); then
    target_recurring_workers="${target_workers}"
  fi

  HEALTHY_QUOTA_POOLS="${healthy_pools}"
  ROTATION_QUOTA_POOLS="${rotation_pools}"
  EFFECTIVE_QUOTA_POOLS="${effective_pools}"
  EFFECTIVE_MAX_CONCURRENT_WORKERS="${target_workers}"
  EFFECTIVE_MAX_CONCURRENT_PR_WORKERS="${target_pr_workers}"
  EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS="${target_recurring_workers}"
  EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT="${target_workers}"

  printf 'DYNAMIC_CONCURRENCY_ENABLED=1\n'
  printf 'DYNAMIC_CONCURRENCY_QUOTA_MODE=failure-driven-dynamic\n'
  printf 'HEALTHY_QUOTA_POOLS=%s\n' "${HEALTHY_QUOTA_POOLS}"
  printf 'ROTATION_QUOTA_POOLS=%s\n' "${ROTATION_QUOTA_POOLS}"
  printf 'EFFECTIVE_QUOTA_POOLS=%s\n' "${EFFECTIVE_QUOTA_POOLS}"
  printf 'EFFECTIVE_MAX_CONCURRENT_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_WORKERS}"
  printf 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=%s\n' "${EFFECTIVE_MAX_CONCURRENT_PR_WORKERS}"
  printf 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=%s\n' "${EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS}"
  printf 'EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT=%s\n' "${EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT}"
}

trap cleanup EXIT

if [[ "${HEARTBEAT_PREFLIGHT_ONLY}" == "1" ]]; then
  if [[ ! -x "${RECOVERY_PREFLIGHT_SCRIPT}" ]]; then
    echo "missing heartbeat preflight script: ${RECOVERY_PREFLIGHT_SCRIPT}" >&2
    exit 1
  fi
  bash "${RECOVERY_PREFLIGHT_SCRIPT}"
  exit $?
fi

run_codex_quota_preflight

# Sync skill files to runtime-home if source has changed since last sync.
# This ensures start-issue-worker.sh and other scripts are always up to date.
if [[ -x "${FLOW_TOOLS_DIR}/ensure-runtime-sync.sh" ]]; then
  "${FLOW_TOOLS_DIR}/ensure-runtime-sync.sh" --quiet 2>/dev/null || true
fi

acquire_lock

reap_orphan_shared_loop_groups

if existing_loop_pid="$(active_shared_loop_pid || true)" && [[ -n "${existing_loop_pid}" ]]; then
  printf 'HEARTBEAT_SKIPPED=shared-loop-active\n'
  printf 'LOOP_PID=%s\n' "${existing_loop_pid}"
  exit 0
fi

if [[ "${RETAINED_WORKTREE_AUDIT_ENABLED}" != "0" ]]; then
  printf '[%s] retained-worktree audit start\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if retained_audit_output="$(
    run_with_timeout "${RETAINED_WORKTREE_AUDIT_TIMEOUT_SECONDS}" \
      bash "${WORKSPACE_DIR}/bin/audit-retained-worktrees.sh" --cleanup 2>&1
  )"; then
    [[ -n "${retained_audit_output}" ]] && printf '%s\n' "${retained_audit_output}"
    printf '[%s] retained-worktree audit end status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  else
    retained_audit_status=$?
    [[ -n "${retained_audit_output:-}" ]] && printf '%s\n' "${retained_audit_output}"
    if [[ "${retained_audit_status}" -eq 124 ]]; then
      printf 'RETAINED_WORKTREE_AUDIT_TIMEOUT=yes\n'
    fi
    printf '[%s] retained-worktree audit end status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${retained_audit_status}"
  fi
fi

if [[ "${AGENT_WORKTREE_AUDIT_ENABLED}" != "0" ]]; then
  printf '[%s] agent-worktree audit start\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if agent_audit_output="$(
    run_with_timeout "${AGENT_WORKTREE_AUDIT_TIMEOUT_SECONDS}" \
      bash "${WORKSPACE_DIR}/bin/audit-agent-worktrees.sh" --cleanup 2>&1
  )"; then
    [[ -n "${agent_audit_output}" ]] && printf '%s\n' "${agent_audit_output}"
    printf '[%s] agent-worktree audit end status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  else
    agent_audit_status=$?
    [[ -n "${agent_audit_output:-}" ]] && printf '%s\n' "${agent_audit_output}"
    if [[ "${agent_audit_status}" -eq 124 ]]; then
      printf 'AGENT_WORKTREE_AUDIT_TIMEOUT=yes\n'
    fi
    printf '[%s] agent-worktree audit end status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${agent_audit_status}"
  fi
fi

derive_dynamic_limits

printf '[%s] shared heartbeat loop start\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
write_shared_loop_status "running" ""
  if ACP_TIMEOUT_CHILD_PID_FILE="${SHARED_LOOP_PID_FILE}" \
  F_LOSNING_TIMEOUT_CHILD_PID_FILE="${SHARED_LOOP_PID_FILE}" \
  run_with_timeout "${HEARTBEAT_LOOP_TIMEOUT_SECONDS}" \
  env \
    ACP_STATE_ROOT="$STATE_ROOT" \
    ACP_ALLOW_INFRA_CI_BYPASS="$ALLOW_INFRA_CI_BYPASS" \
    ACP_HEALTHY_QUOTA_POOLS="$HEALTHY_QUOTA_POOLS" \
    ACP_EFFECTIVE_QUOTA_POOLS="$EFFECTIVE_QUOTA_POOLS" \
    F_LOSNING_STATE_ROOT="$STATE_ROOT" \
    F_LOSNING_ALLOW_INFRA_CI_BYPASS="$ALLOW_INFRA_CI_BYPASS" \
    F_LOSNING_HEALTHY_QUOTA_POOLS="$HEALTHY_QUOTA_POOLS" \
    F_LOSNING_EFFECTIVE_QUOTA_POOLS="$EFFECTIVE_QUOTA_POOLS" \
    bash "${FLOW_TOOLS_DIR}/agent-project-heartbeat-loop" \
      --repo-slug "$REPO_SLUG" \
      --runs-root "$RUNS_ROOT" \
      --state-root "$STATE_ROOT" \
      --memory-dir "$MEMORY_DIR" \
      --issue-prefix "$ISSUE_SESSION_PREFIX" \
      --pr-prefix "$PR_SESSION_PREFIX" \
      --hook-file "$HOOK_FILE" \
      --max-concurrent-workers "$EFFECTIVE_MAX_CONCURRENT_WORKERS" \
      --max-concurrent-heavy-workers "$MAX_CONCURRENT_E2E_WORKERS" \
      --max-concurrent-pr-workers "$EFFECTIVE_MAX_CONCURRENT_PR_WORKERS" \
      --max-recurring-issue-workers "$EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS" \
      --max-concurrent-scheduled-issue-workers "$MAX_CONCURRENT_SCHEDULED_ISSUE_WORKERS" \
      --max-concurrent-scheduled-heavy-workers "$MAX_CONCURRENT_SCHEDULED_HEAVY_WORKERS" \
      --max-concurrent-blocked-recovery-issue-workers "$MAX_CONCURRENT_BLOCKED_RECOVERY_ISSUE_WORKERS" \
      --blocked-recovery-cooldown-seconds "$BLOCKED_RECOVERY_COOLDOWN_SECONDS" \
      --max-open-agent-prs-for-recurring "$MAX_OPEN_AGENT_PRS_FOR_RECURRING" \
      --max-launches-per-pass "$EFFECTIVE_MAX_LAUNCHES_PER_HEARTBEAT" \
      --heavy-running-label "E2E_ISSUE" \
      --heavy-deferred-key "E2E_DEFERRED" \
      --heavy-deferred-message "E2E-heavy issues remain queued until the single e2e slot is free."; then
  write_shared_loop_status "idle" "0"
  printf '[%s] shared heartbeat loop end status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
else
  loop_status=$?
  write_shared_loop_status "idle" "${loop_status}"
  if [[ "${loop_status}" -eq 124 ]]; then
    printf 'HEARTBEAT_LOOP_TIMEOUT=yes\n'
  fi
  printf '[%s] shared heartbeat loop end status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${loop_status}"
  exit "${loop_status}"
fi

# ── Throttled catch-up passes ──────────────────────────────────────────────────
# These scripts fetch merged/closed PRs and linked issues which change rarely.
# Run them at most once every CATCHUP_INTERVAL_SECONDS (default 300 = 5 min)
# to avoid burning API quota on every heartbeat cycle.
CATCHUP_INTERVAL_SECONDS="${ACP_CATCHUP_INTERVAL_SECONDS:-${F_LOSNING_CATCHUP_INTERVAL_SECONDS:-300}}"
CATCHUP_STAMP_FILE="${STATE_ROOT}/last-catchup-timestamp"
_catchup_now="$(date +%s)"
_catchup_last="0"
if [[ -f "${CATCHUP_STAMP_FILE}" ]]; then
  _catchup_last="$(cat "${CATCHUP_STAMP_FILE}" 2>/dev/null || echo 0)"
fi
_catchup_age=$(( _catchup_now - _catchup_last ))

if [[ "${_catchup_age}" -ge "${CATCHUP_INTERVAL_SECONDS}" ]]; then
  printf '[%s] merged-pr catchup start\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if run_with_timeout "${CATCHUP_TIMEOUT_SECONDS}" \
    env \
      ACP_RUNS_ROOT="$RUNS_ROOT" \
      F_LOSNING_RUNS_ROOT="$RUNS_ROOT" \
      bash "${FLOW_TOOLS_DIR}/agent-project-catch-up-merged-prs" \
        --repo-slug "$REPO_SLUG" \
        --state-root "$STATE_ROOT" \
        --hook-file "$HOOK_FILE" \
        --limit 100; then
    printf '[%s] merged-pr catchup end status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  else
    catchup_status=$?
    if [[ "${catchup_status}" -eq 124 ]]; then
      printf 'CATCHUP_TIMEOUT=yes\n'
    fi
    printf '[%s] merged-pr catchup end status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${catchup_status}"
  fi

  printf '[%s] linked-pr issue catchup start\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if run_with_timeout "${CATCHUP_TIMEOUT_SECONDS}" \
    env \
      ACP_RUNS_ROOT="$RUNS_ROOT" \
      F_LOSNING_RUNS_ROOT="$RUNS_ROOT" \
      bash "${FLOW_TOOLS_DIR}/agent-project-catch-up-issue-pr-links" \
        --repo-slug "$REPO_SLUG" \
        --state-root "$STATE_ROOT" \
        --hook-file "$HOOK_FILE" \
        --limit 100; then
    printf '[%s] linked-pr issue catchup end status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  else
    linked_issue_catchup_status=$?
    if [[ "${linked_issue_catchup_status}" -eq 124 ]]; then
      printf 'LINKED_ISSUE_CATCHUP_TIMEOUT=yes\n'
    fi
    printf '[%s] linked-pr issue catchup end status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${linked_issue_catchup_status}"
  fi

  printf '[%s] scheduled-issue retry catchup start\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if run_with_timeout "${CATCHUP_TIMEOUT_SECONDS}" \
    env \
      ACP_RUNS_ROOT="$RUNS_ROOT" \
      F_LOSNING_RUNS_ROOT="$RUNS_ROOT" \
      bash "${FLOW_TOOLS_DIR}/agent-project-catch-up-scheduled-issue-retries" \
        --repo-slug "$REPO_SLUG" \
        --state-root "$STATE_ROOT" \
        --hook-file "$HOOK_FILE" \
        --limit 100; then
    printf '[%s] scheduled-issue retry catchup end status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  else
    scheduled_issue_catchup_status=$?
    if [[ "${scheduled_issue_catchup_status}" -eq 124 ]]; then
      printf 'SCHEDULED_ISSUE_CATCHUP_TIMEOUT=yes\n'
    fi
    printf '[%s] scheduled-issue retry catchup end status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${scheduled_issue_catchup_status}"
  fi

  printf '%s' "${_catchup_now}" >"${CATCHUP_STAMP_FILE}"
else
  printf '[%s] catchup skipped (age=%ss, interval=%ss)\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${_catchup_age}" "${CATCHUP_INTERVAL_SECONDS}"
fi
