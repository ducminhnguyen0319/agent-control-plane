#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-project-cleanup-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-session-registered-worktree.XXXXXX")"
tmpdir="$(cd "$tmpdir" && pwd -P)"
trap 'rm -rf "$tmpdir"' EXIT

real_git="$(command -v git || true)"
if [[ -z "${real_git}" ]]; then
  echo "git is required for registered worktree cleanup test" >&2
  exit 1
fi

shared_bin="$tmpdir/shared/tools/bin"
bin_dir="$tmpdir/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
worktree_path="$tmpdir/worktrees/pr-5"
output_file="$tmpdir/output.txt"

mkdir -p "$shared_bin" "$bin_dir" "$runs_root" "$history_root" "$repo_root" "$(dirname "$worktree_path")"

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

cat >"$bin_dir/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$real_git" "\$@"
EOF
chmod +x "$bin_dir/git"

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" config user.email "test@example.com"
git -C "$repo_root" config user.name "Test User"
git -C "$repo_root" checkout -b main >/dev/null 2>&1
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "seed" >/dev/null 2>&1
git -C "$repo_root" branch cleanup-pr-5 >/dev/null 2>&1
git -C "$repo_root" worktree add "$worktree_path" cleanup-pr-5 >/dev/null 2>&1

PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
SHARED_AGENT_HOME="$tmpdir/shared" \
bash "$shared_bin/agent-project-cleanup-session" \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --worktree "$worktree_path" \
  --mode pr >"$output_file"

grep -q '^CLEANUP_MODE=worktree$' "$output_file"
grep -q '^CLEANUP_STATUS=0$' "$output_file"
test ! -d "$worktree_path"
if git -C "$repo_root" worktree list --porcelain | grep -F -x -q -- "worktree $worktree_path"; then
  echo "registered worktree still present after cleanup" >&2
  exit 1
fi

echo "agent-project-cleanup-session removes registered worktree without rg test passed"
