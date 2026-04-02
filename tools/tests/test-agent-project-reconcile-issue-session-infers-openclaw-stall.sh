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
run_dir="$runs_root/test-issue-2"
retry_reason_file="$tmpdir/retry-reason.txt"

mkdir -p "$bin_dir" "$run_dir" "$history_root" "$repo_root"
git -C "$repo_root" init -q -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test" >/dev/null 2>&1
git -C "$repo_root" config user.email "test@test.com" >/dev/null 2>&1
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -q -m "init" >/dev/null 2>&1

cp "$FLOW_ROOT/tools/bin/agent-project-reconcile-issue-session" "$bin_dir/"
cp "$FLOW_ROOT/tools/bin/flow-config-lib.sh" "$bin_dir/"
cp "$FLOW_ROOT/tools/bin/flow-shell-lib.sh" "$bin_dir/"
cp "$FLOW_ROOT/tools/bin/flow-resident-worker-lib.sh" "$bin_dir/"

cat >"$bin_dir/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${run_dir}/run.env
OUT
EOF
chmod +x "$bin_dir/agent-project-worker-status"

cat >"$bin_dir/agent-project-cleanup-session" <<'CLEANEOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
CLEANEOF
chmod +x "$bin_dir/agent-project-cleanup-session"

cat >"$run_dir/run.env" <<EOF
ISSUE_ID=2
SESSION=test-issue-2
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
UPDATED_AT=2026-04-03T00:00:00Z
EOF

cat >"$run_dir/test-issue-2.log" <<'EOF'
2026-04-03T00:01:00.000Z [openclaw] session started
2026-04-03T00:01:01.000Z [openclaw] loading session
[openclaw] stale-run no-agent-progress-before-stall-threshold elapsed=180s idle=180s
EOF

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

out="$(
  AGENT_CONTROL_PLANE_ROOT="$workspace_root" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$bin_dir/agent-project-reconcile-issue-session" \
    --session test-issue-2 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hook.sh"
)"

grep -q 'FAILURE_REASON=no-agent-progress-before-stall-threshold' <<<"$out"
grep -q 'OUTCOME=blocked' <<<"$out"
grep -q 'ACTION=host-comment-blocker' <<<"$out"
grep -q 'no-agent-progress-before-stall-threshold' "$retry_reason_file"

echo "reconcile infers openclaw stall test passed"
