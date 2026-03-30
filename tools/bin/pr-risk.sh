#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"

PR_NUMBER="${1:?usage: pr-risk.sh PR_NUMBER}"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
ADAPTER_BIN_DIR="${FLOW_SKILL_DIR}/bin"

"${ADAPTER_BIN_DIR}/pr-risk.sh" "$PR_NUMBER"
