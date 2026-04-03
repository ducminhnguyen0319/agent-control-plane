#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

resolved="$(resolve_shared_agent_home "${FLOW_ROOT}")"
[[ "${resolved}" == "${FLOW_ROOT}" ]]

echo "flow shell lib resolve shared agent home test passed"
