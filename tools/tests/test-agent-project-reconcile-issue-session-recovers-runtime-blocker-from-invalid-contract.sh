#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_root="$tmpdir/workspace"
bin_dir="$workspace_root/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
run_dir="$runs_root/fl-issue-runtime-invalid"
retry_reason_file="$tmpdir/retry-reason.txt"

mkdir -p "$bin_dir" "$run_dir" "$history_root" "$repo_root"
git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test"
git -C "$repo_root" config user.email "test@example.com"
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1

cp "$FLOW_ROOT/tools/bin/agent-project-reconcile-issue-session" "$bin_dir/agent-project-reconcile-issue-session"
cp "$FLOW_ROOT/tools/bin/flow-config-lib.sh" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_ROOT/tools/bin/flow-shell-lib.sh" "$bin_dir/flow-shell-lib.sh"
cp "$FLOW_ROOT/tools/bin/flow-resident-worker-lib.sh" "$bin_dir/flow-resident-worker-lib.sh"

cat >"$bin_dir/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${run_dir}/run.env
OUT
EOF
chmod +x "$bin_dir/agent-project-worker-status"

cat >"$bin_dir/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/agent-project-cleanup-session"

cat >"$bin_dir/sync-recurring-issue-checklist.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
CHECKLIST_SYNC_STATUS=noop
CHECKLIST_TOTAL=0
CHECKLIST_CHECKED=0
CHECKLIST_UNCHECKED=0
CHECKLIST_MATCHED_PR_NUMBERS=
OUT
EOF
chmod +x "$bin_dir/sync-recurring-issue-checklist.sh"

cat >"$tmpdir/hook.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() {
  printf '%s\n' "\$1" >"$retry_reason_file"
}
issue_mark_ready() { :; }
issue_remove_running() { :; }
issue_before_blocked() { :; }
issue_after_reconciled() { :; }
EOF
chmod +x "$tmpdir/hook.sh"

cat >"$run_dir/run.env" <<EOF
ISSUE_ID=255
SESSION=fl-issue-runtime-invalid
WORKTREE=$repo_root
BRANCH=main
RESULT_FILE=$run_dir/result.env
EOF

cat >"$run_dir/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-1
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=
UPDATED_AT=2026-04-02T11:00:00Z
EOF

cat >"$run_dir/fl-issue-runtime-invalid.log" <<'EOF'
2026-04-02T11:45:06.875772Z ERROR codex_protocol::protocol: Ignoring invalid cwd "/tmp/missing-worktree" for sandbox writable root: No such file or directory (os error 2)
thread 'tokio-runtime-worker' panicked at protocol/src/protocol.rs:850:69:
/tmp is absolute: Os { code: 2, kind: NotFound, message: "No such file or directory" }
2026-04-02T11:46:20.679580Z ERROR codex_core::util: Custom tool call output is missing for call id: call_demo
__CODEX_EXIT__:0
EOF

out="$(
  AGENT_CONTROL_PLANE_ROOT="$workspace_root" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$bin_dir/agent-project-reconcile-issue-session" \
    --session fl-issue-runtime-invalid \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hook.sh"
)"

grep -q '^STATUS=FAILED$' <<<"$out"
grep -q '^OUTCOME=blocked$' <<<"$out"
grep -q '^ACTION=host-comment-blocker$' <<<"$out"
grep -q '^FAILURE_REASON=worker-environment-blocked$' <<<"$out"
grep -q '^RESULT_CONTRACT_NOTE=missing-worker-result-recovered-worker-environment-blocked$' <<<"$out"
grep -q '^worker-environment-blocked$' "$retry_reason_file"
grep -q '^# Blocker: Worker environment failed before a valid result contract was written$' "$run_dir/issue-comment.md"

echo "issue reconcile recovers runtime blocker from invalid contract test passed"
