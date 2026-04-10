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

# render-flow-config.sh is a passive renderer — it reads env vars but does not
# perform pool selection itself.  Call flow_export_execution_env first so the
# ACP_ACTIVE_PROVIDER_* env vars are populated for the renderer to pick up.
source "${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
export ACP_PROFILE_REGISTRY_ROOT="$profile_home"
export ACP_PROJECT_ID="demo"
config_yaml="$profile_dir/control-plane.yaml"
flow_export_execution_env "$config_yaml"

output="$(
  bash "$SCRIPT"
)"

grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_ORDER=primary fallback$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_NAME=fallback$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_BACKEND=claude$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_MODEL=fallback-sonnet$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOLS_EXHAUSTED=no$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_POOL_SELECTION_REASON=ready$' <<<"$output"
# render-flow-config unsets ACP_CODING_WORKER / ACP_CLAUDE_MODEL, so
# EFFECTIVE_CODING_WORKER reflects the YAML default, not the pool selection.
# Pool-selected backend and model are reported via EFFECTIVE_PROVIDER_POOL_*.
grep -q '^EFFECTIVE_CODING_WORKER=openclaw$' <<<"$output"

echo "render flow config provider pool fallback test passed"
