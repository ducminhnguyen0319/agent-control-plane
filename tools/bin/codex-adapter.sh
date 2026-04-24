#!/usr/bin/env bash
# codex-adapter.sh
# Adapter implementation for Codex (Claude CLI)
# Implements: adapter-interface.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"

# Codex adapter metadata
ADAPTER_ID="codex"
ADAPTER_NAME="Codex (Claude CLI)"
ADAPTER_TYPE="cloud-api"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${CLAUDE_MODEL:-sonnet}"
ADAPTER_BASE_URL=""

# Print adapter info
adapter_info() {
  cat <<EOF
id=${ADAPTER_ID}
name=${ADAPTER_NAME}
type=${ADAPTER_TYPE}
version=${ADAPTER_VERSION}
model=${ADAPTER_MODEL}
base_url=${ADAPTER_BASE_URL}
EOF
}

# Health check: verify claude CLI is available
adapter_health_check() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude CLI not found in PATH"
    return 1
  fi
  
  # Check if API key is set
  if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "WARN: No ANTHROPIC_API_KEY or OPENROUTER_API_KEY found"
    # Don't fail - user might use OAuth
  fi
  
  echo "OK: Codex adapter healthy (claude CLI available)"
  return 0
}

# Run a task using codex (claude CLI)
adapter_run() {
  local mode="${1:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local session="${2:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local worktree="${3:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local prompt_file="${4:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  
  local permission_mode="${CLAUDE_PERMISSION_MODE:-acceptEdits}"
  local timeout_seconds="${CLAUDE_TIMEOUT_SECONDS:-900}"
  local max_attempts="${CLAUDE_MAX_ATTEMPTS:-3}"
  
  echo "Codex adapter: Running session ${session} with model ${ADAPTER_MODEL}"
  
  # Read the prompt
  local prompt
  prompt="$(cat "${prompt_file}")"
  
  # Change to worktree
  cd "${worktree}" || return 1
  
  # Run claude with the prompt
  if ! timeout "${timeout_seconds}" claude \
    --permission-mode "${permission_mode}" \
    --model "${ADAPTER_MODEL}" \
    --print \
    "${prompt}" 2>&1; then
    echo "ERROR: Codex run failed or timed out after ${timeout_seconds}s"
    return 1
  fi
  
  echo "Codex adapter: Session ${session} completed"
  return 0
}

# Status check
adapter_status() {
  local runs_root="${1:?usage: adapter_status RUNS_ROOT SESSION}"
  local session="${2:?usage: adapter_status RUNS_ROOT SESSION}"
  local run_dir="${runs_root}/${session}"
  
  if [[ ! -d "$run_dir" ]]; then
    echo "NOT_FOUND"
    return 1
  fi
  
  # Check for result file
  if [[ -f "$run_dir/result.env" ]]; then
    source "$run_dir/result.env"
    echo "${OUTCOME:-UNKNOWN}"
    return 0
  fi
  
  # Check if claude process is running
  if pgrep -f "claude.*${session}" >/dev/null 2>&1; then
    echo "RUNNING"
    return 0
  fi
  
  echo "UNKNOWN"
  return 0
}

# Self-register: validate this adapter implements required functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Running directly - print info
  adapter_info
  echo "---"
  adapter_health_check
fi
