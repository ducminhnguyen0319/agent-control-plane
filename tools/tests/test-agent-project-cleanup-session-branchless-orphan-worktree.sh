#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-branchless-orphan.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

shared_bin="$tmpdir/shared/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
worktree_path="$worktree_root/pr-5-stale"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$runs_root" "$history_root" "$repo_root" "$worktree_path"

cp "$SCRIPT_SRC" "$shared_bin/agent-project-cleanup-session"
chmod +x "$shared_bin/agent-project-cleanup-session"

cat >"$shared_bin/agent-cleanup-worktree" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$shared_bin/agent-cleanup-worktree"

cat >"$shared_bin/agent-project-archive-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$shared_bin/agent-project-archive-run"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1

printf 'artifact\n' >"$worktree_path/pr-comment.md"

AGENT_PROJECT_WORKTREE_ROOT="$worktree_root" \
SHARED_AGENT_HOME="$tmpdir/shared" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --worktree "$worktree_path" \
  --mode pr >"$output_file"

grep -q '^CLEANUP_MODE=orphan-worktree$' "$output_file"
grep -q '^ORPHAN_FALLBACK_USED=true$' "$output_file"
grep -q '^CLEANUP_STATUS=0$' "$output_file"
test ! -d "$worktree_path"

echo "test-agent-project-cleanup-session-branchless-orphan-worktree: PASS"
