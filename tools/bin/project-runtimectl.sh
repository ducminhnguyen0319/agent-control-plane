#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  project-runtimectl.sh <status|start|stop|restart> --profile-id <id> [options]

Manage runtime processes for one installed profile.

Options:
  --profile-id <id>      Profile id to manage
  --delay-seconds <n>    Delay for start via kick-scheduler (default: 0)
  --wait-seconds <n>     Wait for stop to settle before SIGKILL (default: 10)
  --help                 Show this help
EOF
}

subcommand="${1:-}"
if [[ -z "${subcommand}" ]]; then
  usage >&2
  exit 64
fi
shift || true

profile_id_override=""
delay_seconds="0"
wait_seconds="10"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id_override="${2:-}"; shift 2 ;;
    --delay-seconds) delay_seconds="${2:-}"; shift 2 ;;
    --wait-seconds) wait_seconds="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

case "${subcommand}" in
  status|start|stop|restart) ;;
  *)
    echo "Unknown subcommand: ${subcommand}" >&2
    usage >&2
    exit 64
    ;;
esac

if [[ -n "${profile_id_override}" ]]; then
  export ACP_PROJECT_ID="${profile_id_override}"
  export AGENT_PROJECT_ID="${profile_id_override}"
fi

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "project-runtimectl.sh"; then
  exit 64
fi

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
if [[ ! -f "${CONFIG_YAML}" ]]; then
  requested_profile_id="${profile_id_override:-${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-unknown}}}"
  if [[ "${subcommand}" == "stop" ]]; then
    printf 'ACTION=stop\n'
    printf 'PROFILE_ID=%s\n' "${requested_profile_id}"
    printf 'CONFIG_YAML=%s\n' "${CONFIG_YAML}"
    printf 'REPO_SLUG=\n'
    printf 'RUNS_ROOT=\n'
    printf 'STATE_ROOT=\n'
    printf 'RUNTIME_STATUS=not-installed\n'
    printf 'LAUNCHD_STATE=n/a\n'
    printf 'HEARTBEAT_PID=\n'
    printf 'HEARTBEAT_PARENT_PID=\n'
    printf 'SHARED_LOOP_PID=\n'
    printf 'SUPERVISOR_PID=\n'
    printf 'CONTROLLER_COUNT=0\n'
    printf 'ACTIVE_TMUX_SESSION_COUNT=0\n'
    printf 'PENDING_LAUNCH_COUNT=0\n'
    printf 'CONTROLLER_PIDS=\n'
    printf 'ACTIVE_TMUX_SESSIONS=\n'
    printf 'PENDING_LAUNCH_PIDS=\n'
    exit 0
  fi
  printf 'profile not installed: %s\n' "${requested_profile_id}" >&2
  exit 66
fi
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
SUPERVISOR_PID_FILE="${STATE_ROOT}/runtime-supervisor.pid"
PROFILE_ID_SLUG="$(printf '%s' "${PROFILE_ID}" | tr -c 'A-Za-z0-9._-' '-')"
BOOTSTRAP_SCRIPT="${ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/project-launchd-bootstrap.sh}"
KICK_SCRIPT="${ACP_PROJECT_RUNTIME_KICK_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/kick-scheduler.sh}"
SUPERVISOR_SCRIPT="${ACP_PROJECT_RUNTIME_SUPERVISOR_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/project-runtime-supervisor.sh}"
UPDATE_LABELS_SCRIPT="${ACP_PROJECT_RUNTIME_UPDATE_LABELS_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/agent-github-update-labels}"
TMUX_BIN="${ACP_PROJECT_RUNTIME_TMUX_BIN:-$(command -v tmux || true)}"
LAUNCHCTL_BIN="${ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN:-$(command -v launchctl || true)}"
LAUNCH_AGENTS_DIR="${ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR:-${HOME}/Library/LaunchAgents}"
LAUNCHD_LABEL="${ACP_PROJECT_RUNTIME_LAUNCHD_LABEL:-ai.agent.project.${PROFILE_ID_SLUG}}"
LAUNCHD_PLIST="${ACP_PROJECT_RUNTIME_LAUNCHD_PLIST:-${LAUNCH_AGENTS_DIR}/${LAUNCHD_LABEL}.plist}"

case "${delay_seconds}" in
  ''|*[!0-9]*) echo "--delay-seconds must be numeric" >&2; exit 64 ;;
esac

case "${wait_seconds}" in
  ''|*[!0-9]*) echo "--wait-seconds must be numeric" >&2; exit 64 ;;
esac

pid_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

pid_from_file() {
  local file_path="${1:-}"
  local pid=""
  [[ -f "${file_path}" ]] || return 1
  pid="$(tr -d '[:space:]' <"${file_path}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  if pid_alive "${pid}"; then
    printf '%s\n' "${pid}"
    return 0
  fi
  return 1
}

command_of_pid() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 1
  ps -p "${pid}" -o command= 2>/dev/null | sed 's/^ *//'
}

ppid_of_pid() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 1
  ps -p "${pid}" -o ppid= 2>/dev/null | tr -d '[:space:]'
}

join_by_comma() {
  local first="1"
  local item=""
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    if [[ "${first}" == "1" ]]; then
      printf '%s' "${item}"
      first="0"
    else
      printf ',%s' "${item}"
    fi
  done
  printf '\n'
}

runtime_started() {
  local heartbeat=""
  local shared_loop=""
  local supervisor=""

  heartbeat="$(heartbeat_pid)"
  shared_loop="$(shared_loop_pid)"
  supervisor="$(supervisor_pid)"

  [[ -n "${heartbeat}" || -n "${shared_loop}" || -n "${supervisor}" ]]
}

wait_for_runtime_start() {
  local timeout="${1:?timeout required}"
  local deadline=$(( $(date +%s) + timeout ))

  while (( $(date +%s) <= deadline )); do
    if runtime_started; then
      return 0
    fi
    sleep 1
  done
  return 1
}

tmux_session_exists() {
  local session="${1:-}"
  [[ -n "${TMUX_BIN}" && -n "${session}" ]] || return 1
  "${TMUX_BIN}" has-session -t "${session}" 2>/dev/null
}

collect_run_sessions() {
  local run_env=""
  local session=""
  [[ -d "${RUNS_ROOT}" ]] || return 0
  while IFS= read -r run_env; do
    [[ -n "${run_env}" ]] || continue
    session="$(awk -F= '/^SESSION=/{print $2}' "${run_env}" 2>/dev/null | tail -n 1 | tr -d '\r' || true)"
    if [[ -z "${session}" ]]; then
      session="$(basename "$(dirname "${run_env}")")"
    fi
    [[ -n "${session}" ]] || continue
    printf '%s\n' "${session}"
  done < <(find "${RUNS_ROOT}" -mindepth 2 -maxdepth 2 -type f -name run.env 2>/dev/null | sort -u)
}

collect_active_tmux_sessions() {
  local session=""
  while IFS= read -r session; do
    [[ -n "${session}" ]] || continue
    if tmux_session_exists "${session}"; then
      printf '%s\n' "${session}"
    fi
  done < <(collect_run_sessions)
}

collect_repo_shared_loop_pids() {
  ps -ax -o pid=,command= 2>/dev/null \
    | while read -r pid command; do
        [[ -n "${pid:-}" ]] || continue
        case "${command}" in
          *"agent-project-heartbeat-loop --repo-slug ${REPO_SLUG}"*)
            if pid_alive "${pid}"; then
              printf '%s\n' "${pid}"
            fi
            ;;
        esac
      done
}

collect_controller_pids() {
  local controller_file=""
  local pid=""
  [[ -d "${STATE_ROOT}/resident-workers/issues" ]] || return 0
  while IFS= read -r controller_file; do
    [[ -n "${controller_file}" ]] || continue
    pid="$(awk -F= '/^CONTROLLER_PID=/{print $2}' "${controller_file}" 2>/dev/null | tail -n 1 | tr -d '[:space:]\r' || true)"
    if pid_alive "${pid}"; then
      printf '%s\n' "${pid}"
    fi
  done < <(find "${STATE_ROOT}/resident-workers/issues" -mindepth 2 -maxdepth 2 -type f -name controller.env 2>/dev/null | sort -u)
}

collect_pending_launch_pids() {
  local pid_file=""
  local pid=""
  [[ -d "${STATE_ROOT}/pending-launches" ]] || return 0
  while IFS= read -r pid_file; do
    [[ -n "${pid_file}" ]] || continue
    pid="$(pid_from_file "${pid_file}" || true)"
    if [[ -n "${pid}" ]]; then
      printf '%s\n' "${pid}"
    fi
  done < <(find "${STATE_ROOT}/pending-launches" -mindepth 1 -maxdepth 1 -type f -name '*.pid' 2>/dev/null | sort -u)
}

heartbeat_pid() {
  pid_from_file "${STATE_ROOT}/heartbeat-loop.lock/pid" || true
}

shared_loop_pid() {
  local pid=""
  pid="$(pid_from_file "${STATE_ROOT}/shared-heartbeat-loop.pid" || true)"
  if [[ -n "${pid}" ]]; then
    if command_of_pid "${pid}" | grep -F -- "agent-project-heartbeat-loop --repo-slug ${REPO_SLUG}" >/dev/null 2>&1; then
      printf '%s\n' "${pid}"
      return 0
    fi
    rm -f "${STATE_ROOT}/shared-heartbeat-loop.pid"
  fi
  collect_repo_shared_loop_pids | head -n 1 || true
}

kick_scheduler_pid() {
  pid_from_file "${STATE_ROOT}/kick-scheduler/pid" || true
}

supervisor_pid() {
  pid_from_file "${SUPERVISOR_PID_FILE}" || true
}

heartbeat_parent_pid() {
  local pid=""
  local parent_pid=""
  local parent_command=""
  pid="$(heartbeat_pid)"
  [[ -n "${pid}" ]] || return 0
  parent_pid="$(ppid_of_pid "${pid}" || true)"
  [[ -n "${parent_pid}" ]] || return 0
  parent_command="$(command_of_pid "${parent_pid}" || true)"
  case "${parent_command}" in
    *project-runtime-supervisor.sh*|*agent-scheduler-launchd.sh*|*"agent-project-${PROFILE_ID_SLUG}-launchd.sh"*)
      if pid_alive "${parent_pid}"; then
        printf '%s\n' "${parent_pid}"
      fi
      ;;
  esac
}

launchd_service_enabled_for_profile() {
  [[ -n "${LAUNCHCTL_BIN}" && -x "${LAUNCHCTL_BIN}" ]] || return 1
  [[ -f "${LAUNCHD_PLIST}" ]] || return 1
  return 0
}

launchd_service_state() {
  if ! launchd_service_enabled_for_profile; then
    printf 'n/a\n'
    return 0
  fi
  if "${LAUNCHCTL_BIN}" print "gui/$(id -u)/${LAUNCHD_LABEL}" >/dev/null 2>&1; then
    printf 'running\n'
  else
    printf 'stopped\n'
  fi
}

print_status() {
  local heartbeat=""
  local shared_loop=""
  local heartbeat_parent=""
  local supervisor=""
  local controller_pids=""
  local active_sessions=""
  local pending_pids=""
  local runtime_status="stopped"
  local controller_count="0"
  local active_session_count="0"
  local pending_count="0"
  local launchd_state=""

  heartbeat="$(heartbeat_pid)"
  shared_loop="$(shared_loop_pid)"
  supervisor="$(supervisor_pid)"
  heartbeat_parent="$(heartbeat_parent_pid)"
  controller_pids="$(collect_controller_pids | sort -u)"
  active_sessions="$(collect_active_tmux_sessions | sort -u)"
  pending_pids="$(collect_pending_launch_pids | sort -u)"

  [[ -n "${controller_pids}" ]] && controller_count="$(printf '%s\n' "${controller_pids}" | awk 'NF {c+=1} END {print c+0}')"
  [[ -n "${active_sessions}" ]] && active_session_count="$(printf '%s\n' "${active_sessions}" | awk 'NF {c+=1} END {print c+0}')"
  [[ -n "${pending_pids}" ]] && pending_count="$(printf '%s\n' "${pending_pids}" | awk 'NF {c+=1} END {print c+0}')"

  if [[ -n "${heartbeat}" || -n "${shared_loop}" || -n "${supervisor}" || "${controller_count}" != "0" || "${active_session_count}" != "0" ]]; then
    runtime_status="running"
  fi
  if [[ -z "${heartbeat}" && -z "${supervisor}" && ( -n "${shared_loop}" || "${controller_count}" != "0" || "${active_session_count}" != "0" ) ]]; then
    runtime_status="partial"
  fi

  launchd_state="$(launchd_service_state)"

  printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
  printf 'CONFIG_YAML=%s\n' "${CONFIG_YAML}"
  printf 'REPO_SLUG=%s\n' "${REPO_SLUG}"
  printf 'RUNS_ROOT=%s\n' "${RUNS_ROOT}"
  printf 'STATE_ROOT=%s\n' "${STATE_ROOT}"
  printf 'RUNTIME_STATUS=%s\n' "${runtime_status}"
  printf 'LAUNCHD_STATE=%s\n' "${launchd_state}"
  printf 'LAUNCHD_LABEL=%s\n' "${LAUNCHD_LABEL}"
  printf 'LAUNCHD_PLIST=%s\n' "${LAUNCHD_PLIST}"
  printf 'HEARTBEAT_PID=%s\n' "${heartbeat}"
  printf 'HEARTBEAT_PARENT_PID=%s\n' "${heartbeat_parent}"
  printf 'SHARED_LOOP_PID=%s\n' "${shared_loop}"
  printf 'SUPERVISOR_PID=%s\n' "${supervisor}"
  printf 'CONTROLLER_COUNT=%s\n' "${controller_count}"
  printf 'ACTIVE_TMUX_SESSION_COUNT=%s\n' "${active_session_count}"
  printf 'PENDING_LAUNCH_COUNT=%s\n' "${pending_count}"
  printf 'CONTROLLER_PIDS=%s\n' "$(printf '%s\n' "${controller_pids}" | join_by_comma)"
  printf 'ACTIVE_TMUX_SESSIONS=%s\n' "$(printf '%s\n' "${active_sessions}" | join_by_comma)"
  printf 'PENDING_LAUNCH_PIDS=%s\n' "$(printf '%s\n' "${pending_pids}" | join_by_comma)"
}

terminate_pid_list() {
  local signal_name="${1:?signal required}"
  shift
  local pid=""
  for pid in "$@"; do
    [[ -n "${pid}" ]] || continue
    kill "-${signal_name}" "${pid}" 2>/dev/null || true
  done
}

wait_for_pids_to_exit() {
  local timeout="${1:?timeout required}"
  shift
  if [[ "$#" -eq 0 ]]; then
    return 0
  fi
  local -a pids=("$@")
  local deadline=$(( $(date +%s) + timeout ))
  local pid=""
  local alive="1"

  while (( $(date +%s) <= deadline )); do
    alive="0"
    for pid in "${pids[@]}"; do
      if pid_alive "${pid}"; then
        alive="1"
        break
      fi
    done
    if [[ "${alive}" == "0" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

remove_runtime_pid_files() {
  rm -f "${STATE_ROOT}/shared-heartbeat-loop.pid"
  rm -f "${STATE_ROOT}/kick-scheduler/pid"
  rmdir "${STATE_ROOT}/kick-scheduler" 2>/dev/null || true
  rm -f "${SUPERVISOR_PID_FILE}"
  rm -f "${STATE_ROOT}/heartbeat-loop.lock/pid"
  rmdir "${STATE_ROOT}/heartbeat-loop.lock" 2>/dev/null || true
  find "${STATE_ROOT}/pending-launches" -mindepth 1 -maxdepth 1 -type f -name '*.pid' -delete 2>/dev/null || true
}

clear_running_labels_after_stop() {
  local issue_json=""
  local pr_json=""
  local number=""

  if ! command -v gh >/dev/null 2>&1 || [[ ! -x "${UPDATE_LABELS_SCRIPT}" ]]; then
    return 0
  fi

  issue_json="$(flow_github_issue_list_json "${REPO_SLUG}" open 100 2>/dev/null || printf '[]\n')"
  while IFS= read -r number; do
    [[ -n "${number}" ]] || continue
    bash "${UPDATE_LABELS_SCRIPT}" --repo-slug "${REPO_SLUG}" --number "${number}" --remove agent-running >/dev/null 2>&1 || true
  done < <(jq -r '.[] | select(any(.labels[]?; .name == "agent-running")) | .number' <<<"${issue_json}" 2>/dev/null || true)

  pr_json="$(flow_github_pr_list_json "${REPO_SLUG}" open 100 2>/dev/null || printf '[]\n')"
  while IFS= read -r number; do
    [[ -n "${number}" ]] || continue
    bash "${UPDATE_LABELS_SCRIPT}" --repo-slug "${REPO_SLUG}" --number "${number}" --remove agent-running >/dev/null 2>&1 || true
  done < <(jq -r '.[] | select(any(.labels[]?; .name == "agent-running")) | .number' <<<"${pr_json}" 2>/dev/null || true)
}

stop_runtime() {
  local -a tmux_sessions=()
  local -a pid_targets=()
  local session=""
  local pid=""
  local launchd_stopped="no"

  while IFS= read -r session; do
    [[ -n "${session}" ]] || continue
    tmux_sessions+=("${session}")
  done < <(collect_active_tmux_sessions | sort -u)

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    pid_targets+=("${pid}")
  done < <(
    {
      heartbeat_pid
      heartbeat_parent_pid
      shared_loop_pid
      collect_repo_shared_loop_pids
      kick_scheduler_pid
      supervisor_pid
      collect_controller_pids
      collect_pending_launch_pids
    } | awk 'NF {print}' | sort -u
  )

  if launchd_service_enabled_for_profile; then
    "${LAUNCHCTL_BIN}" bootout "gui/$(id -u)/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
    launchd_stopped="yes"
  fi

  if [[ -n "${TMUX_BIN}" ]]; then
    for session in "${tmux_sessions[@]+"${tmux_sessions[@]}"}"; do
      "${TMUX_BIN}" kill-session -t "${session}" >/dev/null 2>&1 || true
    done
  fi

  terminate_pid_list TERM "${pid_targets[@]+"${pid_targets[@]}"}"
  wait_for_pids_to_exit "${wait_seconds}" "${pid_targets[@]+"${pid_targets[@]}"}" || terminate_pid_list KILL "${pid_targets[@]+"${pid_targets[@]}"}"
  remove_runtime_pid_files
  clear_running_labels_after_stop

  printf 'ACTION=stop\n'
  printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
  printf 'LAUNCHD_STOPPED=%s\n' "${launchd_stopped}"
  printf 'STOPPED_PID_COUNT=%s\n' "$(printf '%s\n' "${pid_targets[@]+"${pid_targets[@]}"}" | awk 'NF {c+=1} END {print c+0}')"
  printf 'STOPPED_TMUX_SESSION_COUNT=%s\n' "$(printf '%s\n' "${tmux_sessions[@]+"${tmux_sessions[@]}"}" | awk 'NF {c+=1} END {print c+0}')"
  printf 'STOPPED_PIDS=%s\n' "$(printf '%s\n' "${pid_targets[@]+"${pid_targets[@]}"}" | join_by_comma)"
  printf 'STOPPED_TMUX_SESSIONS=%s\n' "$(printf '%s\n' "${tmux_sessions[@]+"${tmux_sessions[@]}"}" | join_by_comma)"
}

start_runtime() {
  local kick_output=""
  local fallback_pid=""
  local start_timeout="${ACP_PROJECT_RUNTIME_START_WAIT_SECONDS:-${wait_seconds}}"
  local runtime_started_after_kick="0"
  local supervisor_spawned="0"
  local start_mode="kick-scheduler"

  if runtime_started; then
    printf 'ACTION=start\n'
    printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
    printf 'START_MODE=already-running\n'
    printf 'NOOP=yes\n'
    return 0
  fi

  if launchd_service_enabled_for_profile; then
    local launchd_domain="gui/$(id -u)"
    "${LAUNCHCTL_BIN}" bootout "${launchd_domain}/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
    "${LAUNCHCTL_BIN}" bootstrap "${launchd_domain}" "${LAUNCHD_PLIST}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if "${LAUNCHCTL_BIN}" print "${launchd_domain}/${LAUNCHD_LABEL}" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    "${LAUNCHCTL_BIN}" kickstart -k "${launchd_domain}/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
    printf 'ACTION=start\n'
    printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
    printf 'START_MODE=launchd\n'
    printf 'LAUNCHD_LABEL=%s\n' "${LAUNCHD_LABEL}"
    return 0
  fi

  kick_output="$(ACP_PROJECT_ID="${PROFILE_ID}" AGENT_PROJECT_ID="${PROFILE_ID}" bash "${KICK_SCRIPT}" "${delay_seconds}")"
  if wait_for_runtime_start "${start_timeout}"; then
    runtime_started_after_kick="1"
  fi

  if [[ "${runtime_started_after_kick}" != "1" && -z "$(supervisor_pid)" ]]; then
    mkdir -p "${STATE_ROOT}"
    nohup env ACP_PROJECT_ID="${PROFILE_ID}" AGENT_PROJECT_ID="${PROFILE_ID}" \
      bash "${SUPERVISOR_SCRIPT}" \
        --bootstrap-script "${BOOTSTRAP_SCRIPT}" \
        --pid-file "${SUPERVISOR_PID_FILE}" \
        --delay-seconds "${delay_seconds}" \
        --interval-seconds "${ACP_PROJECT_RUNTIME_SUPERVISOR_INTERVAL_SECONDS:-15}" \
        </dev/null >/dev/null 2>&1 &
    fallback_pid="$!"
    supervisor_spawned="1"
    wait_for_runtime_start "${start_timeout}" || true
  fi

  if [[ "${supervisor_spawned}" == "1" ]]; then
    if [[ "${runtime_started_after_kick}" == "1" ]]; then
      start_mode="kick-scheduler-plus-supervisor"
    else
      start_mode="kick-scheduler-fallback-supervisor"
    fi
  fi

  printf 'ACTION=start\n'
  printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
  printf 'START_MODE=%s\n' "${start_mode}"
  printf '%s\n' "${kick_output}"
  if [[ -n "${fallback_pid}" ]]; then
    printf 'FALLBACK_SUPERVISOR_PID=%s\n' "${fallback_pid}"
  fi
}

case "${subcommand}" in
  status)
    print_status
    ;;
  stop)
    stop_runtime
    print_status
    ;;
  start)
    start_runtime
    print_status
    ;;
  restart)
    stop_runtime >/dev/null
    start_runtime
    print_status
    ;;
esac
