#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"
PROFILE_SMOKE_SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"
repo_root="$tmpdir/repo"

git -C "$tmpdir" init -b main repo >/dev/null 2>&1
git -C "$repo_root" remote add origin https://github.com/right-owner/right-repo.git

bash "$SCAFFOLD_SCRIPT" \
  --profile-home "$profile_home" \
  --profile-id mismatch \
  --repo-slug wrong-owner/wrong-repo \
  --repo-root "$repo_root" \
  --agent-repo-root "$repo_root" \
  --retained-repo-root "$repo_root" \
  >/dev/null

set +e
output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$PROFILE_SMOKE_SCRIPT" --profile-id mismatch 2>&1)"
status=$?
set -e

test "$status" -ne 0
grep -q '^PROFILE_ID=mismatch$' <<<"$output"
grep -q '^PROFILE_STATUS=failed$' <<<"$output"
grep -q 'repo.slug mismatch: config=wrong-owner/wrong-repo origin=right-owner/right-repo' <<<"$output"

echo "profile smoke repo slug mismatch test passed"
