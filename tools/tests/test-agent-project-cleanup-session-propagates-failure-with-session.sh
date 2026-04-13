#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"
ARCHIVE_SRC="${FLOW_ROOT}/tools/bin/agent-project-archive-run"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-failure.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
session="fl-issue-441"
run_dir="$runs_root/$session"
worktree_path="$worktree_root/issue-441"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$run_dir" "$history_root" "$repo_root" "$worktree_path"

cp "$SCRIPT_SRC" "$shared_bin/agent-project-cleanup-session"
cp "$ARCHIVE_SRC" "$shared_bin/agent-project-archive-run"
chmod +x "$shared_bin/agent-project-cleanup-session" "$shared_bin/agent-project-archive-run"

cat >"$shared_bin/agent-cleanup-worktree" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "[agent-cleanup] simulated failure" >&2
exit 23
EOF
chmod +x "$shared_bin/agent-cleanup-worktree"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1

cat >"$run_dir/run.env" <<EOF
SESSION=$session
BRANCH=agent/demo/issue-441
WORKTREE=$worktree_path
RESULT_FILE=$run_dir/result.env
EOF

touch "$worktree_path/README.md"

set +e
AGENT_PROJECT_WORKTREE_ROOT="$worktree_root" \
SHARED_AGENT_HOME="$tmpdir/shared" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --session "$session" \
  --mode issue >"$output_file"
status=$?
set -e

[[ "$status" == "23" ]]
grep -q '^CLEANUP_STATUS=23$' "$output_file"
grep -q '^CLEANUP_ERROR=' "$output_file"

archived_dir="$(awk -F= '/^ARCHIVED_DIR=/{print substr($0, index($0, "=") + 1); exit}' "$output_file")"
[[ -n "$archived_dir" && -d "$archived_dir" ]]
grep -q '^cleanup_status=23$' "$archived_dir/cleanup-warning.txt"
grep -q '^cleanup_mode=' "$archived_dir/cleanup-warning.txt"

echo "agent-project-cleanup-session propagates failure with session test passed"
