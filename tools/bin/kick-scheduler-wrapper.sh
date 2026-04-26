#!/usr/bin/env bash
# Wrapper for kick-scheduler to add timeout and logging
set -euo pipefail

PID_FILE="${1:?PID file required}"
DELAY_SECONDS="${2:?Delay seconds required}"
BOOTSTRAP_SCRIPT="${3:?Bootstrap script required}"
FLOW_SAFE_AUTO_SCRIPT="${4:?Flow safe auto script required}"
REPO_SLUG="${5:?Repo slug required}"
STATE_DIR="${6:?State dir required}"
KICK_TIMEOUT_SECONDS="${ACP_KICK_TIMEOUT_SECONDS:-3600}"
KICK_LOG="${STATE_DIR}/kick-scheduler.log"

trap 'rm -f "$PID_FILE"' EXIT

log() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [wrapper] $*" >>"${KICK_LOG}"
}

# Cross-platform timeout command detection
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
  # macOS with coreutils installed via brew
  TIMEOUT_CMD="gtimeout"
else
  log "WARNING: 'timeout' command not found, bootstrap will run without timeout"
fi

log "Delay ${DELAY_SECONDS}s, timeout ${KICK_TIMEOUT_SECONDS}s (timeout cmd: ${TIMEOUT_CMD:-none})"

sleep "${DELAY_SECONDS}"

# Check for active heartbeat
active_pid="$(ps -ax -o pid=,command= | while read -r pid command; do
  [[ -n "${pid:-}" ]] || continue
  case "$command" in
    *"${BOOTSTRAP_SCRIPT}"*|*"${FLOW_SAFE_AUTO_SCRIPT}"*|*"agent-project-heartbeat-loop --repo-slug ${REPO_SLUG}"*)
      printf "%s\n" "$pid"
      break
      ;;
  esac
done)"

if [[ -n "$active_pid" ]]; then
  log "Active heartbeat found (PID ${active_pid}), skipping"
  exit 0
fi

if [[ -n "${TIMEOUT_CMD}" ]]; then
  log "Starting bootstrap with timeout ${KICK_TIMEOUT_SECONDS}s using ${TIMEOUT_CMD}"
  "${TIMEOUT_CMD}" "${KICK_TIMEOUT_SECONDS}" "${BOOTSTRAP_SCRIPT}" >>"${KICK_LOG}" 2>&1 || true
else
  log "Starting bootstrap without timeout (timeout command not available)"
  "${BOOTSTRAP_SCRIPT}" >>"${KICK_LOG}" 2>&1 || true
fi
log "Bootstrap completed with exit code $?"
