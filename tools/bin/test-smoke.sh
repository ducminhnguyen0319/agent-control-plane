#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  test-smoke.sh [--help]

Run the main smoke gates for the shared agent-control-plane package in one command.

Steps:
  1. check-skill-contracts.sh
  2. tools/tests/test-profile-smoke.sh
  3. tools/tests/test-project-runtimectl.sh

Environment overrides:
  ACP_TEST_SMOKE_CHECK_CONTRACTS_SCRIPT
  ACP_TEST_SMOKE_PROFILE_TEST_SCRIPT
  ACP_TEST_SMOKE_RUNTIMECTL_TEST_SCRIPT
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

check_contracts_script="${ACP_TEST_SMOKE_CHECK_CONTRACTS_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/check-skill-contracts.sh}"
profile_test_script="${ACP_TEST_SMOKE_PROFILE_TEST_SCRIPT:-${FLOW_SKILL_DIR}/tools/tests/test-profile-smoke.sh}"
runtimectl_test_script="${ACP_TEST_SMOKE_RUNTIMECTL_TEST_SCRIPT:-${FLOW_SKILL_DIR}/tools/tests/test-project-runtimectl.sh}"

run_step() {
  local label="${1:?label required}"
  shift
  local status=0

  printf 'SMOKE_STEP=%s\n' "${label}"
  set +e
  "$@"
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    printf 'SMOKE_STEP_STATUS=ok\n'
    return 0
  fi

  printf 'SMOKE_STEP_STATUS=failed\n'
  printf 'FAILED_STEP=%s\n' "${label}"
  printf 'EXIT_CODE=%s\n' "${status}"
  printf 'SMOKE_TEST_STATUS=failed\n'
  return "${status}"
}

run_step "check-skill-contracts" bash "${check_contracts_script}"
run_step "test-profile-smoke" bash "${profile_test_script}"
run_step "test-project-runtimectl" bash "${runtimectl_test_script}"

printf 'SMOKE_TEST_STATUS=ok\n'
