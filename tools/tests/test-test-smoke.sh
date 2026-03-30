#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SMOKE_BIN="${FLOW_ROOT}/tools/bin/test-smoke.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

call_log="${tmpdir}/calls.log"
check_stub="${tmpdir}/check.sh"
profile_stub="${tmpdir}/profile.sh"
runtimectl_stub="${tmpdir}/runtimectl.sh"
fail_stub="${tmpdir}/fail.sh"

write_stub() {
  local path="${1:?path required}"
  local label="${2:?label required}"
  local body="${3:-}"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${label}" >>"${call_log}"
${body}
EOF
  chmod +x "${path}"
}

write_stub "${check_stub}" "check"
write_stub "${profile_stub}" "profile"
write_stub "${runtimectl_stub}" "runtimectl"
write_stub "${fail_stub}" "fail" "exit 23"

success_output="$(
  ACP_TEST_SMOKE_CHECK_CONTRACTS_SCRIPT="${check_stub}" \
  ACP_TEST_SMOKE_PROFILE_TEST_SCRIPT="${profile_stub}" \
  ACP_TEST_SMOKE_RUNTIMECTL_TEST_SCRIPT="${runtimectl_stub}" \
    bash "${SMOKE_BIN}"
)"

grep -q '^SMOKE_STEP=check-skill-contracts$' <<<"${success_output}"
grep -q '^SMOKE_STEP=test-profile-smoke$' <<<"${success_output}"
grep -q '^SMOKE_STEP=test-project-runtimectl$' <<<"${success_output}"
[[ "$(grep -c '^SMOKE_STEP_STATUS=ok$' <<<"${success_output}")" -eq 3 ]]
grep -q '^SMOKE_TEST_STATUS=ok$' <<<"${success_output}"
grep -q '^check$' "${call_log}"
grep -q '^profile$' "${call_log}"
grep -q '^runtimectl$' "${call_log}"

success_calls=()
while IFS= read -r line; do
  success_calls+=("${line}")
done <"${call_log}"
[[ "${success_calls[0]}" == "check" ]]
[[ "${success_calls[1]}" == "profile" ]]
[[ "${success_calls[2]}" == "runtimectl" ]]

: >"${call_log}"

set +e
failure_output="$(
  ACP_TEST_SMOKE_CHECK_CONTRACTS_SCRIPT="${check_stub}" \
  ACP_TEST_SMOKE_PROFILE_TEST_SCRIPT="${fail_stub}" \
  ACP_TEST_SMOKE_RUNTIMECTL_TEST_SCRIPT="${runtimectl_stub}" \
    bash "${SMOKE_BIN}" 2>&1
)"
failure_status=$?
set -e

[[ "${failure_status}" -eq 23 ]]
grep -q '^SMOKE_STEP=check-skill-contracts$' <<<"${failure_output}"
grep -q '^SMOKE_STEP=test-profile-smoke$' <<<"${failure_output}"
grep -q '^SMOKE_STEP_STATUS=failed$' <<<"${failure_output}"
grep -q '^FAILED_STEP=test-profile-smoke$' <<<"${failure_output}"
grep -q '^EXIT_CODE=23$' <<<"${failure_output}"
grep -q '^SMOKE_TEST_STATUS=failed$' <<<"${failure_output}"

failure_calls=()
while IFS= read -r line; do
  failure_calls+=("${line}")
done <"${call_log}"
[[ "${failure_calls[0]}" == "check" ]]
[[ "${failure_calls[1]}" == "fail" ]]
[[ "${#failure_calls[@]}" -eq 2 ]]

echo "test smoke entrypoint test passed"
