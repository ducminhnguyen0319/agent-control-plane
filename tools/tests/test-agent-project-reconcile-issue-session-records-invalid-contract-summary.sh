#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISSUE_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
metadata_file="$tmpdir/resident/metadata.env"

mkdir -p \
  "$shared_bin" \
  "$shared_assets" \
  "$runs_root/demo-issue-654" \
  "$history_root" \
  "$repo_root" \
  "$(dirname "$metadata_file")" \
  "$tmpdir/worktree"

cp "$ISSUE_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-issue-session"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$RESIDENT_LIB" "$shared_bin/flow-resident-worker-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=demo-issue-654\n'
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$runs_root/demo-issue-654/run.env"
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-resident-worker-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session"

cat >"$runs_root/demo-issue-654/run.env" <<EOF
ISSUE_ID=654
WORKTREE=$tmpdir/worktree
BRANCH=agent/demo/issue-654
RESIDENT_WORKER_ENABLED=yes
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
RESIDENT_WORKER_META_FILE=$metadata_file
EOF

cat >"$runs_root/demo-issue-654/result.env" <<'EOF'
OUTCOME=implemented
ACTION=invalid-action
EOF

cat >"$metadata_file" <<'EOF'
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
RESIDENT_LANE_KIND=recurring
RESIDENT_LANE_VALUE=general
ISSUE_ID=654
LAST_STATUS=RUNNING
LAST_OUTCOME=''
LAST_ACTION=''
LAST_FAILURE_REASON=''
LAST_WORKTREE_REUSED=no
EOF

cat >"$tmpdir/issue-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() { :; }
issue_mark_ready() { :; }
issue_after_reconciled() { :; }
EOF
chmod +x "$tmpdir/issue-hook.sh"

output="$(
  SHARED_AGENT_HOME="$shared_agent_home" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session demo-issue-654 \
    --repo-slug example/demo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/issue-hook.sh"
)"

grep -q '^STATUS=FAILED$' <<<"$output"
grep -q '^OUTCOME=invalid-contract$' <<<"$output"
grep -q '^ACTION=queued-issue-retry$' <<<"$output"
grep -q '^FAILURE_REASON=invalid-result-contract$' <<<"$output"
grep -q '^LAST_STATUS=FAILED$' "$metadata_file"
grep -q '^LAST_OUTCOME=invalid-contract$' "$metadata_file"
grep -q '^LAST_ACTION=queued-issue-retry$' "$metadata_file"
grep -q '^LAST_FAILURE_REASON=invalid-result-contract$' "$metadata_file"
grep -q '^RESIDENT_LANE_KIND=recurring$' "$metadata_file"
grep -q '^RESIDENT_LANE_VALUE=general$' "$metadata_file"

echo "agent-project reconcile issue session records invalid contract summary test passed"
