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
  "$runs_root" \
  "$state_root/recurring" \
  "$memory_dir"

printf '101\n' >"$state_root/recurring/last-launched-issue-id"

cat >"$hook_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

heartbeat_list_ready_issue_ids() { printf '101\n'; }
heartbeat_list_blocked_recovery_issue_ids() { :; }
heartbeat_list_open_agent_pr_ids() { :; }
heartbeat_list_running_issue_ids() { :; }
heartbeat_list_exclusive_issue_ids() { :; }
heartbeat_list_exclusive_pr_ids() { :; }

heartbeat_issue_is_heavy() { printf 'no\n'; }
heartbeat_issue_is_recurring() { printf 'yes\n'; }
heartbeat_issue_schedule_interval_seconds() { printf '0\n'; }
heartbeat_issue_is_scheduled() { printf 'no\n'; }
heartbeat_issue_is_exclusive() { printf 'no\n'; }
heartbeat_pr_is_exclusive() { printf 'no\n'; }
heartbeat_sync_pr_labels() { :; }
heartbeat_pr_risk_json() { printf '{"agentLane":"ignore"}\n'; }
heartbeat_sync_issue_labels() { :; }

heartbeat_mark_issue_running() { :; }
heartbeat_issue_launch_failed() { :; }
heartbeat_mark_pr_running() { :; }
heartbeat_clear_pr_running() { :; }

heartbeat_start_issue_worker() {
  local issue_id="${1:?issue id required}"
  printf 'ISSUE:%s\n' "$issue_id" >>"${TEST_EVENTS_LOG:?}"
}
heartbeat_start_pr_merge_repair_worker() { :; }
heartbeat_start_pr_review_worker() { :; }
heartbeat_start_pr_fix_worker() { :; }
heartbeat_start_pr_ci_refresh() { :; }
heartbeat_reconcile_issue() { :; }
heartbeat_reconcile_pr() { :; }
EOF

cat >"$shared_home/tools/bin/agent-project-retry-state" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
READY=yes
LAST_REASON=
OUT
EOF

cat >"$shared_home/tools/bin/provider-cooldown-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
READY=yes
BACKEND=
MODEL=
LAST_REASON=
OUT
EOF

cat >"$shared_home/tools/bin/agent-project-worker-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'STATUS=UNKNOWN\n'
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
  "$shared_home/tools/bin/provider-cooldown-state.sh" \
  "$shared_home/tools/bin/agent-project-worker-status" \
  "$shared_home/tools/bin/agent-project-cleanup-session" \
  "$bin_dir/tmux"

export PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_EVENTS_LOG="$events_log"

output="$(
  SHARED_AGENT_HOME="$shared_home" \
  bash "$SOURCE_SCRIPT" \
    --repo-slug "example/repo" \
    --runs-root "$runs_root" \
    --state-root "$state_root" \
    --memory-dir "$memory_dir" \
    --issue-prefix "fl-issue-" \
    --pr-prefix "fl-pr-" \
    --hook-file "$hook_file" \
    --max-concurrent-workers 2 \
    --max-concurrent-heavy-workers 1 \
    --max-concurrent-pr-workers 1 \
    --max-recurring-issue-workers 1 \
    --max-concurrent-scheduled-issue-workers 0 \
    --max-concurrent-scheduled-heavy-workers 0 \
    --max-concurrent-blocked-recovery-issue-workers 0 \
    --blocked-recovery-cooldown-seconds 900 \
    --max-open-agent-prs-for-recurring 0 \
    --max-launches-per-pass 2
)"

grep -q '^ISSUE:101$' "$events_log"
grep -q '^LAUNCHED_ISSUES=1$' <<<"$output"
grep -q '^LAUNCHED_ISSUE=101$' <<<"$output"

echo "heartbeat loop single recurring issue wraparound test passed"
