#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-resident-protect.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/project/runs"
history_root="$tmpdir/project/history"
state_root="$tmpdir/project/state"
repo_root="$tmpdir/repo"
run_dir="$runs_root/fl-issue-protected"
worktree_root="$tmpdir/project/worktrees"
worktree_path="$worktree_root/issue-615"
lane_dir="$state_root/resident-workers/issues/issue-lane-recurring-general-codex-safe"
cleanup_log="$tmpdir/cleanup.log"
archive_log="$tmpdir/archive.log"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$run_dir" "$history_root" "$lane_dir" "$worktree_path" "$repo_root"

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
printf 'ARCHIVED_DIR=%s\n' "$history_root/fl-issue-protected-archived"
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1
git -C "$worktree_path" init -b main >/dev/null 2>&1

cat >"$run_dir/run.env" <<EOF
SESSION=fl-issue-protected
BRANCH=agent/test/issue-protected
WORKTREE=$worktree_path
RESULT_FILE=$run_dir/result.env
EOF

cat >"$lane_dir/metadata.env" <<EOF
WORKTREE=$lane_dir/worktree
WORKTREE_REALPATH=$worktree_path
ISSUE_ID=255
LAST_STATUS=running
EOF

ln -s "$worktree_path" "$lane_dir/worktree"

SHARED_AGENT_HOME="$tmpdir/shared" \
AGENT_PROJECT_STATE_ROOT="$state_root" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --state-root "$state_root" \
  --session fl-issue-protected \
  --mode issue >"$output_file"

grep -q '^CLEANUP_MODE=protected-resident-worktree$' "$output_file"
test ! -f "$cleanup_log"
test -f "$archive_log"
test -d "$worktree_path"

echo "test-agent-project-cleanup-session-protects-resident-worktree: PASS"
