#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAPSHOT_BIN="${FLOW_ROOT}/tools/bin/render-dashboard-snapshot.py"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
runs_root="$tmpdir/runtime/demo/runs"
state_root="$tmpdir/runtime/demo/state"
run_dir="$runs_root/demo-issue-1"

mkdir -p \
  "$profile_dir" \
  "$run_dir" \
  "$state_root/resident-workers/issues/1" \
  "$state_root/resident-workers/issues/issue-lane-recurring-general-openclaw-safe" \
  "$state_root/retries/providers" \
  "$state_root/scheduled-issues" \
  "$state_root/resident-workers/issue-queue/pending"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo-dashboard"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$runs_root"
  state_root: "$state_root"
  history_root: "$tmpdir/runtime/demo/history"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

cat >"$run_dir/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=1
SESSION=demo-issue-1
MODE=safe
STARTED_AT=2026-03-26T15:00:00Z
CODING_WORKER=openclaw
WORKTREE=/tmp/demo-worktree
BRANCH=agent/demo/issue-1
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
OPENCLAW_MODEL=primary/model
EOF

cat >"$run_dir/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-1
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=''
UPDATED_AT=2026-03-26T15:01:00Z
EOF

cat >"$run_dir/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

cat >"$state_root/resident-workers/issues/1/controller.env" <<'EOF'
ISSUE_ID=1
SESSION=demo-issue-1
CONTROLLER_PID=1234
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=2
CONTROLLER_STATE=waiting-provider
CONTROLLER_REASON=provider-cooldown
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=openclaw
ACTIVE_PROVIDER_MODEL=primary/model
PROVIDER_SWITCH_COUNT=1
PROVIDER_FAILOVER_COUNT=1
PROVIDER_WAIT_COUNT=2
PROVIDER_WAIT_TOTAL_SECONDS=45
PROVIDER_LAST_WAIT_SECONDS=21
UPDATED_AT=2026-03-26T15:02:00Z
EOF

cat >"$state_root/resident-workers/issues/issue-lane-recurring-general-openclaw-safe/metadata.env" <<'EOF'
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ISSUE_ID=1
CODING_WORKER=openclaw
TASK_COUNT=7
LAST_STATUS=running
LAST_STARTED_AT=2026-03-26T15:00:00Z
LAST_RUN_SESSION=demo-issue-1
EOF

cat >"$state_root/retries/providers/openclaw-primary-model.env" <<'EOF'
ATTEMPTS=2
NEXT_ATTEMPT_EPOCH=4102444800
NEXT_ATTEMPT_AT=2100-01-01T00:00:00Z
LAST_REASON=provider-quota-limit
UPDATED_AT=2026-03-26T15:03:00Z
EOF

cat >"$state_root/scheduled-issues/1.env" <<'EOF'
INTERVAL_SECONDS=600
LAST_STARTED_AT=2026-03-26T15:00:00Z
NEXT_DUE_AT=2026-03-26T15:10:00Z
UPDATED_AT=2026-03-26T15:00:00Z
EOF

cat >"$state_root/resident-workers/issue-queue/pending/issue-2.env" <<'EOF'
ISSUE_ID=2
SESSION=demo-issue-2
UPDATED_AT=2026-03-26T15:04:00Z
EOF

snapshot="$(ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" python3 "$SNAPSHOT_BIN" --pretty)"

grep -q '"profile_count": 1' <<<"$snapshot"
grep -q '"id": "demo"' <<<"$snapshot"
grep -q '"repo_slug": "example/demo-dashboard"' <<<"$snapshot"
grep -q '"session": "demo-issue-1"' <<<"$snapshot"
grep -q '"state": "waiting-provider"' <<<"$snapshot"
grep -q '"provider_failover_count": 1' <<<"$snapshot"
grep -q '"provider_wait_total_seconds": 45' <<<"$snapshot"
grep -q '"provider_key": "openclaw-primary-model"' <<<"$snapshot"
grep -q '"queued_issues": 1' <<<"$snapshot"
grep -q '"implemented_runs": 1' <<<"$snapshot"
grep -q '"live_resident_controllers": 0' <<<"$snapshot"
grep -q '"controller_live": false' <<<"$snapshot"
grep -q '"result_kind": "implemented"' <<<"$snapshot"
grep -q '"result_label": "Implemented"' <<<"$snapshot"

echo "render dashboard snapshot test passed"
