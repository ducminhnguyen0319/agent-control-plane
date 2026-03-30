#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-skip.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
worktree_path="$tmpdir/worktrees/issue-441"
session="fl-issue-441"
run_dir="$runs_root/$session"
archive_dir="$history_root/${session}-archived"
cleanup_log="$tmpdir/cleanup.log"

mkdir -p "$shared_bin" "$run_dir" "$history_root" "$repo_root" "$worktree_path"

cp "$SCRIPT_SRC" "$shared_bin/agent-project-cleanup-session"
chmod +x "$shared_bin/agent-project-cleanup-session"

cat >"$shared_bin/agent-cleanup-worktree" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$cleanup_log"
exit 7
EOF
chmod +x "$shared_bin/agent-cleanup-worktree"

cat >"$shared_bin/agent-project-archive-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

runs_root=""
history_root=""
session=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs-root) runs_root="${2:-}"; shift 2 ;;
    --history-root) history_root="${2:-}"; shift 2 ;;
    --session) session="${2:-}"; shift 2 ;;
    --remove-file) shift 2 ;;
    *) shift ;;
  esac
done

archive_dir="${history_root}/${session}-archived"
mv "${runs_root}/${session}" "${archive_dir}"
printf 'ARCHIVE_DIR=%s\n' "$archive_dir"
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null
git -C "$repo_root" checkout -b main >/dev/null

cat >"$run_dir/run.env" <<EOF
SESSION=$session
BRANCH=agent/alpha/issue-441
WORKTREE=$worktree_path
RESULT_FILE=$run_dir/result.env
EOF

printf 'artifact\n' >"$run_dir/result.env"
printf 'keep me\n' >"$worktree_path/README.md"

output="$(
  SHARED_AGENT_HOME="$tmpdir/shared" \
  bash "$shared_bin/agent-project-cleanup-session" \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --session "$session" \
    --mode issue \
    --skip-worktree-cleanup
)"

grep -q '^SESSION=fl-issue-441$' <<<"$output"
grep -q '^SKIP_WORKTREE_CLEANUP=true$' <<<"$output"
grep -q '^CLEANUP_MODE=archived-only$' <<<"$output"
grep -q "^ARCHIVE_DIR=$archive_dir$" <<<"$output"
test -d "$worktree_path"
test ! -d "$run_dir"
test -d "$archive_dir"
test ! -s "$cleanup_log"

echo "test-agent-project-cleanup-session-skip-worktree-cleanup: PASS"
