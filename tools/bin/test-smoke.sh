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
  2. profile-smoke.sh against a temporary scaffolded profile registry
  3. project-runtimectl.sh status against a temporary scaffolded profile

Environment overrides:
  ACP_TEST_SMOKE_CHECK_CONTRACTS_SCRIPT
  ACP_TEST_SMOKE_PROFILE_SMOKE_SCRIPT
  ACP_TEST_SMOKE_RUNTIMECTL_SCRIPT
  ACP_TEST_SMOKE_SCAFFOLD_PROFILE_SCRIPT
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

check_contracts_script="${ACP_TEST_SMOKE_CHECK_CONTRACTS_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/check-skill-contracts.sh}"
profile_smoke_script="${ACP_TEST_SMOKE_PROFILE_SMOKE_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/profile-smoke.sh}"
runtimectl_script="${ACP_TEST_SMOKE_RUNTIMECTL_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/project-runtimectl.sh}"
scaffold_profile_script="${ACP_TEST_SMOKE_SCAFFOLD_PROFILE_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/scaffold-profile.sh}"

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

if [[ -f "${check_contracts_script}" ]]; then
  run_step "check-skill-contracts" bash "${check_contracts_script}"
else
  printf 'SMOKE_STEP=%s\n' "check-skill-contracts"
  printf 'SMOKE_STEP_STATUS=%s\n' "skipped"
fi

run_profile_smoke_fixture() (
  set -euo pipefail
  local tmpdir=""
  local profile_home=""

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
  profile_home="${tmpdir}/profiles"

  bash "${scaffold_profile_script}" \
    --profile-home "${profile_home}" \
    --profile-id smoke-alpha \
    --repo-slug example/smoke-alpha >/dev/null

  ACP_PROFILE_REGISTRY_ROOT="${profile_home}" \
    bash "${profile_smoke_script}" --profile-id smoke-alpha >/dev/null
)

run_runtimectl_fixture() (
  set -euo pipefail
  local tmpdir=""
  local profile_home=""
  local runtime_root=""
  local profile_id="smoke-runtime"
  local output=""

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
  profile_home="${tmpdir}/profiles"
  runtime_root="${tmpdir}/runtime/${profile_id}"

  bash "${scaffold_profile_script}" \
    --profile-home "${profile_home}" \
    --profile-id "${profile_id}" \
    --repo-slug example/${profile_id} \
    --agent-root "${runtime_root}" \
    --agent-repo-root "${runtime_root}/repo" \
    --worktree-root "${runtime_root}/worktrees" >/dev/null

  output="$(
    ACP_PROFILE_REGISTRY_ROOT="${profile_home}" \
      bash "${runtimectl_script}" status --profile-id "${profile_id}"
  )"

  grep -q "^PROFILE_ID=${profile_id}\$" <<<"${output}"
  grep -q '^RUNTIME_STATUS=' <<<"${output}"
)

run_step "profile-smoke" run_profile_smoke_fixture
run_step "project-runtimectl" run_runtimectl_fixture

printf 'SMOKE_TEST_STATUS=ok\n'
