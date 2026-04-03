#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-clear-stale-realpath.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/project/runs"
history_root="$tmpdir/project/history"
state_root="$tmpdir/project/state"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/project/worktrees"
worktree_path="$worktree_root/issue-438"
lane_dir="$state_root/resident-workers/issues/issue-lane-scheduled-3600-codex-safe"
run_dir="$runs_root/demo-issue-438"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$history_root" "$lane_dir" "$repo_root" "$worktree_root" "$worktree_path" "$run_dir"

cp "$SCRIPT_SRC" "$shared_bin/agent-project-cleanup-session"
chmod +x "$shared_bin/agent-project-cleanup-session"

cat >"$shared_bin/agent-cleanup-worktree" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) path="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$path" ]]; then
  rm -rf "$path"
fi
EOF
chmod +x "$shared_bin/agent-cleanup-worktree"

cat >"$shared_bin/agent-project-archive-run" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ARCHIVED_DIR=%s\n' "$history_root/demo-archived"
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1
git -C "$worktree_path" init -b main >/dev/null 2>&1

cat >"$run_dir/run.env" <<EOF
SESSION=demo-issue-438
BRANCH=agent/test/issue-438
WORKTREE=$worktree_path
RESULT_FILE=$run_dir/result.env
EOF

cat >"$lane_dir/metadata.env" <<EOF
WORKTREE=$lane_dir/worktree
WORKTREE_REALPATH=$worktree_path
ISSUE_ID=438
LAST_STATUS=SUCCEEDED
LAST_OUTCOME=reported
EOF

bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --state-root "$state_root" \
  --session demo-issue-438 \
  --mode issue >"$output_file"

grep -Eq '^CLEANUP_MODE=(branch|orphan-worktree|worktree)$' "$output_file"
test ! -d "$worktree_path"
grep -q "^WORKTREE_REALPATH=''$" "$lane_dir/metadata.env"

echo "test-agent-project-cleanup-session-clears-stale-resident-worktree-realpath: PASS"
