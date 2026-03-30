#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

KIND="${1:?usage: retry-state.sh issue|pr ID get|schedule|clear [reason]}"
ITEM_ID="${2:?usage: retry-state.sh issue|pr ID get|schedule|clear [reason]}"
ACTION="${3:?usage: retry-state.sh issue|pr ID get|schedule|clear [reason]}"
REASON="${4:-}"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
COOLDOWNS="$(flow_resolve_retry_cooldowns "${CONFIG_YAML}")"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"

ACP_AGENT_ROOT="$AGENT_ROOT" \
ACP_STATE_ROOT="$STATE_ROOT" \
ACP_RETRY_COOLDOWNS="$COOLDOWNS" \
exec bash "${FLOW_TOOLS_DIR}/agent-project-retry-state" \
  --state-root "$STATE_ROOT" \
  --kind "$KIND" \
  --item-id "$ITEM_ID" \
  --action "$ACTION" \
  --reason "$REASON" \
  --cooldowns "$COOLDOWNS"
