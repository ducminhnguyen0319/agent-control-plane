#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

DELAY_SECONDS="${1:-5}"
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "kick-scheduler.sh"; then
  exit 64
fi
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
BOOTSTRAP_SCRIPT="${ACP_BOOTSTRAP_SCRIPT:-${FLOW_BOOTSTRAP_SCRIPT:-${AGENT_SCHEDULER_BOOTSTRAP_SCRIPT:-$HOME/.agent-runtime/control-plane/workspace/bin/agent-scheduler-launchd.sh}}"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_SAFE_AUTO_SCRIPT="${ACP_FLOW_HEARTBEAT_SCRIPT:-${FLOW_HEARTBEAT_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/heartbeat-safe-auto.sh}}"
STATE_DIR="${ACP_SCHEDULER_KICK_STATE_DIR:-${STATE_ROOT}/kick-scheduler}"
PID_FILE="${STATE_DIR}/pid"

# Validate repo configuration before proceeding
if [[ -z "${REPO_SLUG:-}" ]]; then
  echo "KICK_STATUS=repo-not-configured"
  exit 1
fi

# Basic format check for repo slug
if [[ "${REPO_SLUG}" =~ ^https?:// ]]; then
  # Looks like a URL - validate it's reachable
  if ! curl -s --connect-timeout 5 "${REPO_SLUG}" >/dev/null 2>&1; then
    echo "KICK_STATUS=repo-not-reachable"
    exit 1
  fi
elif [[ ! "${REPO_SLUG}" =~ ^[^/]+/[^/]+$ ]]; then
  # Not a valid owner/repo format
  echo "KICK_STATUS=repo-invalid-format"
  exit 1
fi

mkdir -p "${STATE_DIR}"

active_heartbeat_pid() {
  ps -ax -o pid=,command= \
    | while read -r pid command; do
        [[ -n "${pid:-}" ]] || continue
        case "$command" in
          *"${BOOTSTRAP_SCRIPT}"*|*"${WORKSPACE_DIR}/bin/heartbeat-safe-auto.sh"*|*"${FLOW_SAFE_AUTO_SCRIPT}"*|*"agent-project-heartbeat-loop --repo-slug ${REPO_SLUG}"*)
            printf '%s\n' "$pid"
            return 0
            ;;
        esac
      done
}

if active_pid="$(active_heartbeat_pid)"; [[ -n "$active_pid" ]]; then
  printf 'KICK_STATUS=active-heartbeat\n'
  printf 'PID=%s\n' "$active_pid"
  exit 0
fi

if [[ -f "${PID_FILE}" ]]; then
  existing_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    printf 'KICK_STATUS=already-pending\n'
    printf 'PID=%s\n' "${existing_pid}"
    exit 0
  fi
fi

export DELAY_SECONDS BOOTSTRAP_SCRIPT FLOW_SAFE_AUTO_SCRIPT PID_FILE REPO_SLUG
nohup bash -lc '
  trap '\''rm -f "$PID_FILE"'\'' EXIT
  sleep "$DELAY_SECONDS"
  active_pid="$(ps -ax -o pid=,command= | while read -r pid command; do
    [[ -n "${pid:-}" ]] || continue
    case "$command" in
      *"$BOOTSTRAP_SCRIPT"*|*"$FLOW_SAFE_AUTO_SCRIPT"*|*"agent-project-heartbeat-loop --repo-slug $REPO_SLUG"*)
        printf "%s\n" "$pid"
        break
        ;;
    esac
  done)"
  if [[ -n "$active_pid" ]]; then
    exit 0
  fi
  "$BOOTSTRAP_SCRIPT" >/dev/null 2>&1 || true
' >/dev/null 2>&1 &

bg_pid="$!"
printf '%s\n' "${bg_pid}" >"${PID_FILE}"
printf 'KICK_STATUS=scheduled\n'
printf 'PID=%s\n' "${bg_pid}"
