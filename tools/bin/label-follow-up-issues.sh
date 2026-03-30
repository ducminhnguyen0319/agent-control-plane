#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

SESSION="${1:?usage: label-follow-up-issues.sh SESSION}"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
ADAPTER_BIN_DIR="${FLOW_SKILL_DIR}/bin"

ACP_RUNS_ROOT="$RUNS_ROOT" F_LOSNING_RUNS_ROOT="$RUNS_ROOT" "${ADAPTER_BIN_DIR}/label-follow-up-issues.sh" "$SESSION"
