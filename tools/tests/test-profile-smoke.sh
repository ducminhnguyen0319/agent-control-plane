#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"

bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id alpha --repo-slug example/alpha >/dev/null
bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id demo --repo-slug example/demo-platform >/dev/null

output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SCRIPT")"

grep -q '^PROFILE_ID=alpha$' <<<"$output"
grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q '^PROFILE_STATUS=ok$' <<<"$output"
grep -q '^PROFILE_SMOKE_STATUS=ok$' <<<"$output"

claude_output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  bash "$SCAFFOLD_SCRIPT" \
    --profile-id claude-demo \
    --repo-slug example/claude-demo \
    --coding-worker claude \
    --claude-timeout-seconds 321 \
    --claude-max-attempts 4 \
    --claude-retry-backoff-seconds 9 \
    >/dev/null
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SCRIPT" --profile-id claude-demo
)"

grep -q '^PROFILE_ID=claude-demo$' <<<"$claude_output"
grep -q '^CODING_WORKER=claude$' <<<"$claude_output"
grep -q '^PROFILE_STATUS=ok$' <<<"$claude_output"
grep -q '^PROFILE_SMOKE_STATUS=ok$' <<<"$claude_output"

# Keep the repo smoke lane honest by running the operator-facing runtime/dashboard
# harness alongside the profile validation checks.
bash "${FLOW_ROOT}/tools/tests/test-control-plane-dashboard-runtime-smoke.sh" >/dev/null

echo "profile smoke test passed"
