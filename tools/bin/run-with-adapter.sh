#!/usr/bin/env bash
# run-with-adapter.sh
# Generic runner that uses the adapter interface
# Usage: run-with-adapter.sh ADAPTER_SCRIPT MODE SESSION WORKTREE PROMPT_FILE

set -euo pipefail

ADAPTER_SCRIPT="${1:?usage: run-with-adapter.sh ADAPTER_SCRIPT MODE SESSION WORKTREE PROMPT_FILE}"
MODE="${2:?usage: run-with-adapter.sh ADAPTER_SCRIPT MODE SESSION WORKTREE PROMPT_FILE}"
SESSION="${3:?usage: run-with-adapter.sh ADAPTER_SCRIPT MODE SESSION WORKTREE PROMPT_FILE}"
WORKTREE="${4:?usage: run-with-adapter.sh ADAPTER_SCRIPT MODE SESSION WORKTREE PROMPT_FILE}"
PROMPT_FILE="${5:?usage: run-with-adapter.sh ADAPTER_SCRIPT MODE SESSION WORKTREE PROMPT_FILE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load adapter interface
source "${SCRIPT_DIR}/adapter-interface.sh"

# Load adapter implementation
adapter_load "${ADAPTER_SCRIPT}"

# Validate adapter
if ! adapter_validate; then
  echo "ERROR: Adapter validation failed"
  exit 1
fi

# Print adapter info
echo "=== Using Adapter ==="
adapter_info
echo "===================="

# Run the task
adapter_run "${MODE}" "${SESSION}" "${WORKTREE}" "${PROMPT_FILE}"
