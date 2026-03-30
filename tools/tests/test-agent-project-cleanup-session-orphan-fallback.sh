#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-orphan.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
session="fl-issue-440"
run_dir="$runs_root/$session"
worktree_path="$worktree_root/issue-440"
cleanup_log="$tmpdir/cleanup.log"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$run_dir" "$history_root" "$repo_root" "$worktree_path"

cp "$SCRIPT_SRC" "$shared_bin/agent-project-cleanup-session"
chmod +x "$shared_bin/agent-project-cleanup-session"

cat >"$shared_bin/agent-cleanup-worktree" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$cleanup_log"
if [[ " \$* " == *" --path "* ]]; then
  echo "[agent-cleanup] Branch agent/alpha/issue-440 is not associated with a dedicated worktree." >&2
  echo "[agent-cleanup] Refusing to trust explicit --path '$worktree_path' without a Git-resolved branch worktree." >&2
  exit 1
fi
echo "[agent-cleanup] cleanup complete"
EOF
chmod +x "$shared_bin/agent-cleanup-worktree"

cat >"$shared_bin/agent-project-archive-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
session=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) session="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'ARCHIVED_SESSION=%s\n' "$session"
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null
git -C "$repo_root" checkout -b main >/dev/null

cat >"$run_dir/run.env" <<EOF
SESSION=$session
BRANCH=agent/alpha/issue-440
WORKTREE=$worktree_path
RESULT_FILE=$run_dir/result.env
EOF

touch "$worktree_path/README.md"

AGENT_PROJECT_WORKTREE_ROOT="$worktree_root" \
SHARED_AGENT_HOME="$tmpdir/shared" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --session "$session" \
  --mode issue >"$output_file"

grep -q '^SESSION=fl-issue-440$' "$output_file"
grep -q '^CLEANUP_MODE=orphan-worktree$' "$output_file"
grep -q '^ORPHAN_FALLBACK_USED=true$' "$output_file"
grep -q '^CLEANUP_STATUS=0$' "$output_file"
grep -q '^ARCHIVED_SESSION=fl-issue-440$' "$output_file"

test ! -d "$worktree_path"

first_call="$(sed -n '1p' "$cleanup_log")"
second_call="$(sed -n '2p' "$cleanup_log")"
[[ "$first_call" == *"--path $worktree_path"* ]]
[[ "$second_call" != *"--path $worktree_path"* ]]

echo "test-agent-project-cleanup-session-orphan-fallback: PASS"
