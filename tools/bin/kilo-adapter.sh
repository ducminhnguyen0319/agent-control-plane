#!/usr/bin/env bash
# kilo-adapter.sh
# Adapter implementation for Kilo Code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"
source "${SCRIPT_DIR}/adapter-capabilities.sh"

ADAPTER_ID="kilo"
ADAPTER_NAME="Kilo Code"
ADAPTER_TYPE="cloud-api"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${KILO_MODEL:-anthropic/claude-sonnet-4-20250514}"

# Kilo capabilities
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
  if ! command -v kilo >/dev/null 2>&1; then
    echo "ERROR: kilo CLI not found in PATH"
    return 1
  fi
  
  # Verify kilo can actually run (version check)
  if ! kilo --version >/dev/null 2>&1; then
    echo "ERROR: kilo CLI cannot run (check installation)"
    return 1
  fi
  
  local version
  version="$(kilo --version 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    echo "WARN: Could not detect kilo version"
  else
    echo "INFO: Kilo version: $version"
  fi
  
  # Verify model is specified
  if [[ -z "${ADAPTER_MODEL}" ]]; then
    echo "WARN: No model specified for Kilo adapter"
  fi
  
  echo "OK: Kilo adapter healthy (model: ${ADAPTER_MODEL})"
  return 0
}

adapter_run() {
  local mode="${1:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local session="${2:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local worktree="${3:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  local prompt_file="${4:?usage: adapter_run MODE SESSION WORKTREE PROMPT_FILE}"
  
  # Validate prompt file
  if [[ ! -f "${prompt_file}" ]]; then
    echo "ERROR: Prompt file not found: ${prompt_file}"
    return 1
  fi
  if [[ ! -s "${prompt_file}" ]]; then
    echo "ERROR: Prompt file is empty: ${prompt_file}"
    return 1
  fi
  
  local timeout_seconds="${KILO_TIMEOUT_SECONDS:-900}"
  
  echo "Kilo adapter: Running session ${session} with model ${ADAPTER_MODEL}"
  
  cd "${worktree}" || return 1
  
  prompt="$(cat "${prompt_file}")"
  
  # Run kilo and capture output
  local output
  if ! output="$(timeout "${timeout_seconds}" kilo --model "${ADAPTER_MODEL}" "${prompt}" 2>&1)"; then
    echo "ERROR: Kilo run failed or timed out after ${timeout_seconds}s"
    return 1
  fi
  
  # Validate JSON stream output (kilo outputs JSON events)
  if ! echo "$output" | python3 -c "import sys, json; [json.loads(line) for line in sys.stdin if line.strip()]" 2>/dev/null; then
    echo "WARN: Kilo output is not valid JSON stream"
  else
    echo "INFO: Kilo output validated as JSON stream"
  fi
  
  echo "Kilo adapter: Session ${session} completed"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  adapter_info
  echo "---"
  adapter_health_check
fi
