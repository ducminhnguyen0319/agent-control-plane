#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-active-resident.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/project/runs"
history_root="$tmpdir/project/history"
state_root="$tmpdir/project/state"
repo_root="$tmpdir/repo"
run_dir="$runs_root/fl-issue-active-resident"
worktree_root="$tmpdir/project/worktrees"
candidate_worktree="$worktree_root/issue-255"
other_worktree="$worktree_root/issue-257"
lane_dir="$state_root/resident-workers/issues/issue-lane-recurring-general-codex-safe"
cleanup_log="$tmpdir/cleanup.log"
archive_log="$tmpdir/archive.log"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$run_dir" "$history_root" "$lane_dir" "$candidate_worktree" "$other_worktree" "$repo_root"

cp "$SCRIPT_SRC" "$shared_bin/agent-project-cleanup-session"
chmod +x "$shared_bin/agent-project-cleanup-session"

cat >"$shared_bin/agent-cleanup-worktree" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'cleanup-called\n' >>"$cleanup_log"
EOF
chmod +x "$shared_bin/agent-cleanup-worktree"

cat >"$shared_bin/agent-project-archive-run" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'archive-called\n' >>"$archive_log"
printf 'ARCHIVED_DIR=%s\n' "$history_root/fl-issue-active-resident-archived"
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1
git -C "$candidate_worktree" init -b main >/dev/null 2>&1
git -C "$other_worktree" init -b main >/dev/null 2>&1

cat >"$run_dir/run.env" <<EOF
SESSION=fl-issue-active-resident
BRANCH=agent/test/issue-active-resident
WORKTREE=$lane_dir/worktree
WORKTREE_REALPATH=$candidate_worktree
RESIDENT_WORKER_ENABLED=yes
RESULT_FILE=$run_dir/result.env
EOF

cat >"$run_dir/runner.env" <<'EOF'
RUNNER_STATE=running
THREAD_ID=
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=
LAST_FAILURE_REASON=
UPDATED_AT=2026-04-02T12:00:00Z
EOF

cat >"$lane_dir/metadata.env" <<EOF
WORKTREE=$lane_dir/worktree
WORKTREE_REALPATH=$other_worktree
ISSUE_ID=257
LAST_STATUS=running
EOF

ln -s "$other_worktree" "$lane_dir/worktree"

SHARED_AGENT_HOME="$tmpdir/shared" \
AGENT_PROJECT_STATE_ROOT="$state_root" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --state-root "$state_root" \
  --session fl-issue-active-resident \
  --worktree "$candidate_worktree" \
  --mode issue >"$output_file"

grep -q '^CLEANUP_MODE=protected-resident-worktree$' "$output_file"
test ! -f "$cleanup_log"
test -f "$archive_log"
test -d "$candidate_worktree"

echo "test-agent-project-cleanup-session-protects-active-resident-run-worktree: PASS"
