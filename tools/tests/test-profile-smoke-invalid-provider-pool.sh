#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_SMOKE_SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"
profile_dir="$profile_home/pool-bad"
mkdir -p "$profile_dir"

cat >"$profile_dir/control-plane.yaml" <<EOF
id: "pool-bad"
repo:
  slug: "example/pool-bad"
  root: "${tmpdir}/repo"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/pool-bad"
  agent_repo_root: "${tmpdir}/repo"
  worktree_root: "${tmpdir}/worktrees"
  runs_root: "${tmpdir}/runtime/pool-bad/runs"
  state_root: "${tmpdir}/runtime/pool-bad/state"
session_naming:
  issue_prefix: "pool-bad-issue-"
  pr_prefix: "pool-bad-pr-"
  issue_branch_prefix: "agent/pool-bad/issue"
  pr_worktree_branch_prefix: "agent/pool-bad/pr"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 600
  provider_pool_order: "primary fallback"
  provider_pools:
    primary:
      coding_worker: "openclaw"
      openclaw:
        model: "primary/model"
        thinking: "adaptive"
        timeout_seconds: 600
    fallback:
      coding_worker: "claude"
      claude:
        model: "fallback-sonnet"
        permission_mode: "dontAsk"
        effort: "medium"
        max_attempts: 3
        retry_backoff_seconds: 30
EOF

printf '# bad profile\n' >"$profile_dir/README.md"

set +e
output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$PROFILE_SMOKE_SCRIPT" --profile-id pool-bad 2>&1)"
status=$?
set -e

test "$status" -eq 1
grep -q '^PROFILE_ID=pool-bad$' <<<"$output"
grep -q '^PROFILE_STATUS=failed$' <<<"$output"
grep -q '^FAILURE=provider pool fallback is invalid$' <<<"$output"
grep -q '^FAILURE=provider_pool.fallback.claude.timeout_seconds missing$' <<<"$output"
grep -q '^PROFILE_SMOKE_STATUS=failed$' <<<"$output"

echo "profile smoke invalid provider pool test passed"
