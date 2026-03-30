#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARED_BIN="${FLOW_ROOT}/tools/bin"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
mkdir -p "$bin_dir" "$runs_root/fl-issue-501" "$history_root" "$repo_root"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" ]]; then
  exit 0
fi
echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh"

cat >"$runs_root/fl-issue-501/run.env" <<'EOF'
ISSUE_ID=501
SESSION=fl-issue-501
WORKTREE=/tmp/mock-worktree
EOF

cat >"$runs_root/fl-issue-501/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
ISSUE_ID=501
EOF

cat >"$runs_root/fl-issue-501/issue-comment.md" <<'EOF'
Why it was blocked:

- Needs focused follow-up issues
EOF

cat >"$bin_dir/agent-project-worker-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${TEST_RUN_DIR:?}/run.env
OUT
EOF
chmod +x "$bin_dir/agent-project-worker-status"

cat >"$bin_dir/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/agent-project-cleanup-session"

hook_file="$tmpdir/hooks.sh"
before_blocked_flag="$tmpdir/before-blocked.flag"
cat >"$hook_file" <<EOF
issue_before_blocked() {
  : >"$before_blocked_flag"
}
issue_schedule_retry() { return 0; }
issue_mark_blocked() { return 0; }
issue_after_reconciled() { return 0; }
EOF

out="$(
  PATH="$bin_dir:$PATH" \
  TEST_RUN_DIR="$runs_root/fl-issue-501" \
  bash "$SHARED_BIN/agent-project-reconcile-issue-session" \
    --session fl-issue-501 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

test -f "$before_blocked_flag"
grep -q '^STATUS=SUCCEEDED$' <<<"$out"
grep -q '^FAILURE_REASON=issue-worker-blocked$' <<<"$out"

echo "issue reconcile before-blocked hook test passed"
