#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Core shell library (required by all modules)
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"
flow_export_project_env_aliases

# Load modules in dependency order
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-profile-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-forge-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-provider-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-session-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-execution-lib.sh"
