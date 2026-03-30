#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

profile_registry_root="${tmpdir}/profiles"
mkdir -p "${profile_registry_root}"

if ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_ALLOW_IMPLICIT_PROFILE_SELECTION=1 \
  bash "${RUNTIMECTL_BIN}" status --profile-id missing-demo >"${tmpdir}/stdout.log" 2>"${tmpdir}/stderr.log"; then
  echo "expected missing profile status to fail" >&2
  exit 1
fi

grep -q 'profile not installed: missing-demo' "${tmpdir}/stderr.log"
[[ ! -s "${tmpdir}/stdout.log" ]]

stop_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_ALLOW_IMPLICIT_PROFILE_SELECTION=1 \
    bash "${RUNTIMECTL_BIN}" stop --profile-id missing-demo
)"

grep -q 'ACTION=stop' <<<"${stop_output}"
grep -q 'PROFILE_ID=missing-demo' <<<"${stop_output}"
grep -q 'RUNTIME_STATUS=not-installed' <<<"${stop_output}"
grep -q 'CONFIG_YAML=.*/missing-demo/control-plane.yaml' <<<"${stop_output}"

if ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_ALLOW_IMPLICIT_PROFILE_SELECTION=1 \
  bash "${RUNTIMECTL_BIN}" start --profile-id missing-demo >"${tmpdir}/start.stdout.log" 2>"${tmpdir}/start.stderr.log"; then
  echo "expected missing profile start to fail" >&2
  exit 1
fi

grep -q 'profile not installed: missing-demo' "${tmpdir}/start.stderr.log"
[[ ! -s "${tmpdir}/start.stdout.log" ]]

if ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_ALLOW_IMPLICIT_PROFILE_SELECTION=1 \
  bash "${RUNTIMECTL_BIN}" restart --profile-id missing-demo >"${tmpdir}/restart.stdout.log" 2>"${tmpdir}/restart.stderr.log"; then
  echo "expected missing profile restart to fail" >&2
  exit 1
fi

grep -q 'profile not installed: missing-demo' "${tmpdir}/restart.stderr.log"
[[ ! -s "${tmpdir}/restart.stdout.log" ]]

echo "project runtimectl missing profile test passed"
