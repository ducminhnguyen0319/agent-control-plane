#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
ADAPTER_BIN_DIR="${FLOW_SKILL_DIR}/bin"

exec "${ADAPTER_BIN_DIR}/audit-issue-routing.sh" "$@"
