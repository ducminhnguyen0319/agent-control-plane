#!/usr/bin/env bash
# ollama-adapter.sh
# Adapter implementation for Ollama local models
# Implements: adapter-interface.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adapter-interface.sh"
source "${SCRIPT_DIR}/adapter-capabilities.sh"

# Ollama adapter metadata
ADAPTER_ID="ollama"
ADAPTER_NAME="Ollama Local Models"
ADAPTER_TYPE="local-model"
ADAPTER_VERSION="1.0.0"
ADAPTER_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"
ADAPTER_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"

# Ollama capabilities
ADAPTER_CAP_LOCAL_MODEL=true
ADAPTER_CAP_STREAMING=true
ADAPTER_CAP_TOOLS_SUPPORT=true
ADAPTER_CAP_CONTEXT_WINDOW=32768  # Default, will be detected dynamically
ADAPTER_CAP_MAX_TIMEOUT=3600

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

# Health check: verify ollama is running and model is available
adapter_health_check() {
  # Check if ollama is running
  if ! curl -sf "${ADAPTER_BASE_URL}/api/tags" >/dev/null 2>&1; then
    echo "ERROR: Ollama not reachable at ${ADAPTER_BASE_URL}"
    return 1
  fi
  
  # Check if model is available (try to pull if not)
  if ! ollama list 2>/dev/null | grep -q "${ADAPTER_MODEL}"; then
    echo "WARN: Model ${ADAPTER_MODEL} not found locally. Attempting pull..."
    if ! ollama pull "${ADAPTER_MODEL}" 2>&1; then
      echo "ERROR: Failed to pull model ${ADAPTER_MODEL}"
      return 1
    fi
  fi
  
  # Detect context window and update capability dynamically
  local context_window
  # Ollama API returns context_length inside model_info with architecture prefix
  # e.g., qwen2.context_length, llama.context_length, etc.
  if command -v jq &>/dev/null; then
    context_window="$(curl -sf "${ADAPTER_BASE_URL}/api/show" -d "{\"name\":\"${ADAPTER_MODEL}\"}" 2>/dev/null | jq -r '.model_info // {} | to_entries[] | select(.key | endswith("context_length")) | .value' 2>/dev/null | head -1 || true)"
  else
    # Fallback: use grep for common patterns
    context_window="$(curl -sf "${ADAPTER_BASE_URL}/api/show" -d "{\"name\":\"${ADAPTER_MODEL}\"}" 2>/dev/null | grep -o '"[a-z]*\.context_length":[0-9]*' | head -1 | grep -o '[0-9]*$' || true)"
  fi
  if [[ -n "$context_window" ]]; then
    ADAPTER_CAP_CONTEXT_WINDOW="$context_window"
    echo "INFO: Detected context window: $context_window tokens"
  else
    echo "WARN: Could not detect context window from Ollama API"
  fi
  
  echo "OK: Ollama healthy, model ${ADAPTER_MODEL} available"
  return 0
}

# Run a task using ollama
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
  
  local timeout_seconds="${OLLAMA_TIMEOUT_SECONDS:-900}"
  
  echo "Ollama adapter: Running session ${session} with model ${ADAPTER_MODEL}"
  
  # Read the prompt
  local prompt
  prompt="$(cat "${prompt_file}")"
  
  # Run ollama with the prompt
  # Use perl for timeout on macOS (which lacks GNU timeout)
  if command -v timeout >/dev/null 2>&1; then
    if ! timeout "${timeout_seconds}" ollama run "${ADAPTER_MODEL}" "${prompt}" 2>&1; then
      echo "ERROR: Ollama run failed or timed out after ${timeout_seconds}s"
      return 1
    fi
  elif command -v perl >/dev/null 2>&1; then
    if ! perl -e "alarm ${timeout_seconds}; exec @ARGV" ollama run "${ADAPTER_MODEL}" "${prompt}" 2>&1; then
      echo "ERROR: Ollama run failed or timed out after ${timeout_seconds}s"
      return 1
    fi
  else
    # No timeout available, run without timeout
    if ! ollama run "${ADAPTER_MODEL}" "${prompt}" 2>&1; then
      echo "ERROR: Ollama run failed"
      return 1
    fi
  fi
  
  echo "Ollama adapter: Session ${session} completed"
  return 0
}

# Status check (override default)
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
  
  # Check if ollama process is running
  if pgrep -f "ollama run ${ADAPTER_MODEL}" >/dev/null 2>&1; then
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
