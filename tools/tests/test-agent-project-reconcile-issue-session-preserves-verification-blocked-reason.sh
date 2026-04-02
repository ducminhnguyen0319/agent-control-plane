#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
shared_bin="$shared_home/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
bin_dir="$tmpdir/bin"
retry_reason_file="$tmpdir/retry-reason.txt"
blocked_flag="$tmpdir/blocked.flag"
posted_comment_file="$tmpdir/posted-comment.md"

mkdir -p "$shared_bin" "$runs_root/fl-issue-88" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-issue-88/run.env" <<'EOF'
ISSUE_ID=88
SESSION=fl-issue-88
WORKTREE=/tmp/mock-worktree
EOF

cat >"$runs_root/fl-issue-88/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$runs_root/fl-issue-88/issue-comment.md" <<'EOF'
# Blocker: Verification requirements were not satisfied

Host publication stopped this cycle because the branch did not carry the required verification signal for a safe recurring issue PR.

Why it was blocked:
- the verification guard could not confirm the expected checks for this change
- recurring issue publication should stop rather than open an unverifiable PR
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-issue-88/run.env
OUT
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_bin/flow-resident-worker-lib.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

cat >"$tmpdir/hooks.sh" <<EOF
issue_schedule_retry() {
  printf '%s\n' "\$1" >"${retry_reason_file}"
}
issue_mark_blocked() {
  : >"${blocked_flag}"
}
issue_after_reconciled() { :; }
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" && "${2:-}" == "repos/example/repo/issues/88/comments" ]]; then
  shift 2
  body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f)
        if [[ "${2:-}" == body=* ]]; then
          body="${2#body=}"
          shift 2
          continue
        fi
        ;;
    esac
    shift
  done
  printf '%s\n' "${body}" >"${TEST_POSTED_COMMENT_FILE:?}"
  exit 0
fi
exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/flow-resident-worker-lib.sh" \
  "$bin_dir/gh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_POSTED_COMMENT_FILE="$posted_comment_file" \
  bash "$SCRIPT" \
    --session fl-issue-88 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hooks.sh"
)"

test "$(cat "$retry_reason_file")" = "verification-guard-blocked"
test -f "$blocked_flag"
grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
grep -q '^ACTION=host-comment-blocker$' <<<"$output"
grep -q '^FAILURE_REASON=verification-guard-blocked$' <<<"$output"
test -f "$posted_comment_file"
grep -q '^# Blocker: Verification requirements were not satisfied$' "$posted_comment_file"

echo "issue reconcile preserves verification blocked reason test passed"
