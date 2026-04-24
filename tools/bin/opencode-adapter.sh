#!/usr/bin/env bash
# opencode-adapter.sh
# Adapter implementation for OpenCode (Crush)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"

ADAPTER_ID="opencode"
ADAPTER_NAME="OpenCode (Crush)"
ADAPTER_TYPE="cloud-api"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${OPENCODE_MODEL:-anthropic/claude-sonnet-4-20250514}"

adapter_info() {
  cat <<EOF
id=${ADAPTER_ID}
name=${ADAPTER_NAME}
type=${ADAPTER_TYPE}
version=${ADAPTER_VERSION}
model=${ADAPTER_MODEL}
EOF
}

adapter_health_check() {
  if ! command -v crush >/dev/null 2>&1; then
    echo "ERROR: crush CLI not found in PATH"
    return 1
  fi
  echo "OK: OpenCode adapter healthy"
  return 0
}

adapter_run() {
  local mode="${1:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local session="${2:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local worktree="${3:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local prompt_file="${4:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  
  local timeout_seconds="${OPENCODE_TIMEOUT_SECONDS:-900}"
  
  echo "OpenCode adapter: Running session ${session}"
  
  cd "${worktree}" || return 1
  
  prompt="$(cat "${prompt_file}")"
  
  if ! timeout "${timeout_seconds}" crush --model "${ADAPTER_MODEL}" "${prompt}" 2>&1; then
    echo "ERROR: OpenCode run failed"
    return 1
  fi
  
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  adapter_info
  echo "---"
  adapter_health_check
fi
