#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

SESSION="${1:?usage: capture-worker.sh SESSION [LINES]}"
LINES="${2:-80}"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"

exec bash "${FLOW_TOOLS_DIR}/agent-project-capture-worker" \
  --runs-root "$RUNS_ROOT" \
  --session "$SESSION" \
  --lines "$LINES"
