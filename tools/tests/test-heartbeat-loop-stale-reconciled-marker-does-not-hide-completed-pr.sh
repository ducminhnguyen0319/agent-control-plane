#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-heartbeat-loop"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
hook_file="$tmpdir/heartbeat-hooks.sh"
bin_dir="$tmpdir/bin"
runs_root="$tmpdir/runs"
state_root="$tmpdir/state"
memory_dir="$tmpdir/memory"
events_log="$tmpdir/events.log"

mkdir -p \
  "$shared_home/tools/bin" \
  "$bin_dir" \
  "$runs_root/fl-pr-101" \
  "$state_root" \
  "$memory_dir"

cat >"$runs_root/fl-pr-101/run.env" <<'EOF'
SESSION=fl-pr-101
STARTED_AT=2026-04-02T01:40:00Z
EOF

cat >"$runs_root/fl-pr-101/reconciled.ok" <<'EOF'
STARTED_AT=2026-04-02T01:35:00Z
RECONCILED_AT=2026-04-02T01:36:00Z
EOF

cat >"$hook_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

heartbeat_list_ready_issue_ids() { :; }
heartbeat_list_blocked_recovery_issue_ids() { :; }
heartbeat_list_open_agent_pr_ids() { :; }
heartbeat_list_running_issue_ids() { :; }
heartbeat_list_exclusive_issue_ids() { :; }
heartbeat_list_exclusive_pr_ids() { :; }

heartbeat_issue_is_heavy() { printf 'no\n'; }
heartbeat_issue_is_recurring() { printf 'no\n'; }
heartbeat_issue_schedule_interval_seconds() { printf '0\n'; }
heartbeat_issue_is_scheduled() { printf 'no\n'; }
heartbeat_issue_is_exclusive() { printf 'no\n'; }
heartbeat_pr_is_exclusive() { printf 'no\n'; }
heartbeat_pr_risk_json() { printf '{"agentLane":"ignore"}\n'; }
heartbeat_sync_issue_labels() { :; }
heartbeat_sync_pr_labels() { :; }

heartbeat_mark_issue_running() { :; }
heartbeat_issue_launch_failed() { :; }
heartbeat_mark_pr_running() { :; }
heartbeat_clear_pr_running() { :; }

heartbeat_start_issue_worker() { :; }
heartbeat_start_pr_review_worker() { :; }
heartbeat_start_pr_merge_repair_worker() { :; }
heartbeat_start_pr_fix_worker() { :; }
heartbeat_start_pr_ci_refresh() { :; }
heartbeat_reconcile_issue() { :; }
heartbeat_reconcile_pr() {
  local session="${1:?session required}"
  printf 'RECONCILE:%s\n' "$session" >>"${TEST_EVENTS_LOG:?}"
}
EOF

cat >"$shared_home/tools/bin/agent-project-retry-state" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
READY=no
LAST_REASON=
OUT
EOF

cat >"$shared_home/tools/bin/agent-project-worker-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=fl-pr-101\n'
printf 'STATUS=FAILED\n'
EOF

cat >"$shared_home/tools/bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list-sessions" ]]; then
  exit 1
fi
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF

chmod +x \
  "$hook_file" \
  "$shared_home/tools/bin/agent-project-retry-state" \
  "$shared_home/tools/bin/agent-project-worker-status" \
  "$shared_home/tools/bin/agent-project-cleanup-session" \
  "$bin_dir/tmux"

export PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_EVENTS_LOG="$events_log"

SHARED_AGENT_HOME="$shared_home" \
bash "$SOURCE_SCRIPT" \
  --repo-slug "example/repo" \
  --runs-root "$runs_root" \
  --state-root "$state_root" \
  --memory-dir "$memory_dir" \
  --issue-prefix "fl-issue-" \
  --pr-prefix "fl-pr-" \
  --hook-file "$hook_file" \
  --max-concurrent-workers 0 \
  --max-concurrent-heavy-workers 0 \
  --max-concurrent-pr-workers 0 \
  --max-recurring-issue-workers 0 \
  --max-concurrent-scheduled-issue-workers 0 \
  --max-concurrent-scheduled-heavy-workers 0 \
  --max-concurrent-blocked-recovery-issue-workers 0 \
  --blocked-recovery-cooldown-seconds 900 \
  --max-open-agent-prs-for-recurring 0 \
  --max-launches-per-pass 0 \
  >/dev/null

grep -q '^RECONCILE:fl-pr-101$' "$events_log"

echo "heartbeat loop stale reconciled marker test passed"
