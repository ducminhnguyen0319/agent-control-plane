#!/usr/bin/env bash
# pi-adapter.sh
# Adapter implementation for Pi CLI (OpenRouter)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"

ADAPTER_ID="pi"
ADAPTER_NAME="Pi Coding Agent"
ADAPTER_TYPE="cloud-api"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${PI_MODEL:-openrouter/qwen/qwen3.5-plus:free}"

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
  if ! command -v pi >/dev/null 2>&1; then
    echo "ERROR: pi CLI not found in PATH"
    return 1
  fi
  
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "WARN: OPENROUTER_API_KEY not set"
  fi
  
  echo "OK: Pi adapter healthy"
  return 0
}

adapter_run() {
  local mode="${1:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local session="${2:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local worktree="${3:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local prompt_file="${4:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  
  local timeout_seconds="${PI_TIMEOUT_SECONDS:-900}"
  
  echo "Pi adapter: Running session ${session}"
  
  cd "${worktree}" || return 1
  
  prompt="$(cat "${prompt_file}")"
  
  if ! timeout "${timeout_seconds}" pi --model "${ADAPTER_MODEL}" "${prompt}" 2>&1; then
    echo "ERROR: Pi run failed"
    return 1
  fi
  
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  adapter_info
  echo "---"
  adapter_health_check
fi
