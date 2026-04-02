#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-active.XXXXXX")"
cleanup() {
  tmux kill-session -t fl-pr-active-cleanup >/dev/null 2>&1 || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
run_dir="$runs_root/fl-pr-active-cleanup"
cleanup_log="$tmpdir/cleanup.log"
archive_log="$tmpdir/archive.log"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$run_dir" "$history_root" "$repo_root"

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
printf 'ARCHIVED_DIR=/tmp/should-not-run\n'
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1

cat >"$run_dir/run.env" <<'EOF'
SESSION=fl-pr-active-cleanup
BRANCH=agent/test/pr-active
WORKTREE=/tmp/should-not-clean
RESULT_FILE=/tmp/should-not-remove
EOF

tmux new-session -d -s fl-pr-active-cleanup 'sleep 10'

SHARED_AGENT_HOME="$tmpdir/shared" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --session fl-pr-active-cleanup \
  --mode pr >"$output_file"

grep -q '^ACTIVE_TMUX_SESSION=true$' "$output_file"
grep -q '^CLEANUP_MODE=deferred-active-session$' "$output_file"
test ! -f "$cleanup_log"
test ! -f "$archive_log"
test -d "$run_dir"

echo "test-agent-project-cleanup-session-defers-active-session: PASS"
