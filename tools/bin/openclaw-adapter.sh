#!/usr/bin/env bash
# openclaw-adapter.sh
# Adapter implementation for OpenClaw.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"
source "${SCRIPT_DIR}/adapter-capabilities.sh"

ADAPTER_ID="openclaw"
ADAPTER_NAME="OpenClaw"
ADAPTER_TYPE="cloud-api"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${OPENCLAW_MODEL:-openrouter/qwen/qwen3.5-plus:free}"

# OpenClaw capabilities
ADAPTER_CAP_CLOUD_API=true
ADAPTER_CAP_STREAMING=true
ADAPTER_CAP_JSON_OUTPUT=true
ADAPTER_CAP_RESIDENT_MODE=true
ADAPTER_CAP_MAX_TIMEOUT=900

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
  if ! command -v openclaw >/dev/null 2>&1; then
    echo "ERROR: openclaw CLI not found in PATH"
    return 1
  fi
  echo "OK: OpenClaw adapter healthy"
  return 0
}

adapter_run() {
  local mode="${1:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local session="${2:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local worktree="${3:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local prompt_file="${4:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  
  local timeout_seconds="${OPENCLAW_TIMEOUT_SECONDS:-900}"
  
  echo "OpenClaw adapter: Running session ${session}"
  
  cd "${worktree}" || return 1
  
  prompt="$(cat "${prompt_file}")"
  
  if ! timeout "${timeout_seconds}" openclaw --model "${ADAPTER_MODEL}" "${prompt}" 2>&1; then
    echo "ERROR: OpenClaw run failed"
    return 1
  fi
  
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  adapter_info
  echo "---"
  adapter_health_check
fi
