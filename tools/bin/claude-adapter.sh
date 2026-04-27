#!/usr/bin/env bash
# claude-adapter.sh
# Adapter implementation for Claude CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"
source "${SCRIPT_DIR}/adapter-capabilities.sh"

ADAPTER_ID="claude"
ADAPTER_NAME="Claude CLI"
ADAPTER_TYPE="cloud-api"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${CLAUDE_MODEL:-sonnet}"

# Claude capabilities
ADAPTER_CAP_CLOUD_API=true
ADAPTER_CAP_STREAMING=true
ADAPTER_CAP_JSON_OUTPUT=true
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
  if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude CLI not found in PATH"
    return 1
  fi
  echo "OK: Claude adapter healthy"
  return 0
}

adapter_run() {
  local mode="${1:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local session="${2:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local worktree="${3:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local prompt_file="${4:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  
  local permission_mode="${CLAUDE_PERMISSION_MODE:-acceptEdits}"
  local timeout_seconds="${CLAUDE_TIMEOUT_SECONDS:-900}"
  
  echo "Claude adapter: Running session ${session}"

  cd "${worktree}" || return 1

  local sandbox_subdir="${ACP_SANDBOX_SUBDIR:-.openclaw-artifacts}"
  local sandbox_run_dir="${worktree%/}/${sandbox_subdir}/${session}"
  mkdir -p "${sandbox_run_dir}" 2>/dev/null || true
  export ACP_SESSION="${session}"
  export ACP_RUN_DIR="${sandbox_run_dir}"
  export ACP_RESULT_FILE="${sandbox_run_dir}/result.env"
  export F_LOSNING_SESSION="${session}"
  export F_LOSNING_RUN_DIR="${sandbox_run_dir}"
  export F_LOSNING_RESULT_FILE="${sandbox_run_dir}/result.env"

  prompt="$(cat "${prompt_file}")"

  if ! adapter_run_with_timeout "${timeout_seconds}" claude \
    --permission-mode "${permission_mode}" \
    --model "${ADAPTER_MODEL}" \
    --print \
    "${prompt}" 2>&1; then
    echo "ERROR: Claude run failed"
    return 1
  fi
  
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  adapter_info
  echo "---"
  adapter_health_check
fi
