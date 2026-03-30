#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_SMOKE_SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"

ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SCAFFOLD_SCRIPT" \
  --profile-id claude-bad \
  --repo-slug example/claude-bad \
  --coding-worker claude >/dev/null

perl -0pi -e 's/timeout_seconds: 900/timeout_seconds: 0/' "$profile_home/claude-bad/control-plane.yaml"

set +e
output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$PROFILE_SMOKE_SCRIPT" --profile-id claude-bad 2>&1)"
status=$?
set -e

test "$status" -eq 1
grep -q '^PROFILE_ID=claude-bad$' <<<"$output"
grep -q '^PROFILE_STATUS=failed$' <<<"$output"
grep -q '^FAILURE=effective.claude.timeout_seconds must be a positive integer$' <<<"$output"
grep -q '^PROFILE_SMOKE_STATUS=failed$' <<<"$output"

echo "profile smoke invalid claude config test passed"
