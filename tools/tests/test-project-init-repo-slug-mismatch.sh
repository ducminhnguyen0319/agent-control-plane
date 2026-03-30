#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_INIT_BIN="${FLOW_ROOT}/tools/bin/project-init.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

repo_root="${tmpdir}/repo"
git -C "${tmpdir}" init -b main repo >/dev/null 2>&1
git -C "${repo_root}" remote add origin https://github.com/right-owner/right-repo.git

set +e
output="$(
  bash "${PROJECT_INIT_BIN}" \
    --profile-id mismatch \
    --repo-slug wrong-owner/wrong-repo \
    --repo-root "${repo_root}" \
    --agent-repo-root "${repo_root}" \
    2>&1
)"
status=$?
set -e

test "${status}" -ne 0
grep -q 'project-init repo slug mismatch: config=wrong-owner/wrong-repo origin=right-owner/right-repo' <<<"${output}"

echo "project init repo slug mismatch test passed"
