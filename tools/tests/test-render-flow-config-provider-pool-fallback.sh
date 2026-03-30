#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"
profile_dir="$profile_home/demo"
state_root="$tmpdir/runtime/demo/state"
mkdir -p "$profile_dir" "$state_root/retries/providers"

cat >"$profile_dir/control-plane.yaml" <<EOF
id: "demo"
repo:
  slug: "example/demo"
  root: "${tmpdir}/repo"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo"
  agent_repo_root: "${tmpdir}/repo"
  worktree_root: "${tmpdir}/worktrees"
  runs_root: "${tmpdir}/runtime/demo/runs"
  state_root: "${state_root}"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
  issue_branch_prefix: "agent/demo/issue"
  pr_worktree_branch_prefix: "agent/demo/pr"
execution:
  coding_worker: "openclaw"
  provider_quota:
    cooldowns: "300,900"
  provider_pool_order: "primary fallback"
  provider_pools:
    primary:
      coding_worker: "openclaw"
      openclaw:
        model: "primary/model"
        thinking: "adaptive"
        timeout_seconds: 321
    fallback:
      coding_worker: "claude"
      claude:
        model: "fallback-sonnet"
        permission_mode: "dontAsk"
        effort: "high"
        timeout_seconds: 777
        max_attempts: 5
        retry_backoff_seconds: 12
EOF

printf '# demo\n' >"$profile_dir/README.md"

future_epoch=$(( $(date +%s) + 3600 ))
cat >"$state_root/retries/providers/openclaw-primary-model.env" <<EOF
ATTEMPTS=1
NEXT_ATTEMPT_EPOCH=${future_epoch}
NEXT_ATTEMPT_AT=2099-01-01T00:00:00Z
LAST_REASON=provider-quota-limit
UPDATED_AT=2099-01-01T00:00:00Z
EOF

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_PROJECT_ID="demo" \
  bash "$SCRIPT"
)"

grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_ORDER=primary fallback$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_NAME=fallback$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_BACKEND=claude$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_MODEL=fallback-sonnet$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOLS_EXHAUSTED=no$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_SELECTION_REASON=ready$' <<<"$output"
grep -q '^EFFECTIVE_CODING_WORKER=claude$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_MODEL=fallback-sonnet$' <<<"$output"

echo "render flow config provider pool fallback test passed"
