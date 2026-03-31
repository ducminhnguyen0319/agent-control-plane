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
hook_file="$tmpdir/hooks.sh"
provider_log="$tmpdir/provider.log"
retry_reason_file="$tmpdir/retry-reason.txt"
ready_flag="$tmpdir/ready.flag"
posted_comment_file="$tmpdir/posted-comment.md"

mkdir -p "$shared_bin" "$runs_root/fl-issue-77" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-issue-77/run.env" <<'EOF'
ISSUE_ID=77
SESSION=fl-issue-77
CODING_WORKER=openclaw
OPENCLAW_MODEL=openrouter/stepfun/step-3.5-flash:free
WORKTREE=/tmp/mock-worktree
EOF

cat >"$runs_root/fl-issue-77/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
DETAIL=provider-quota-limit
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=FAILED
FAILURE_REASON=provider-quota-limit
META_FILE=${runs_root}/fl-issue-77/run.env
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

cat >"$shared_bin/provider-cooldown-state.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${provider_log}"
printf 'READY=no\n'
EOF

cat >"$hook_file" <<EOF
issue_schedule_retry() {
  printf '%s\n' "\$1" >"${retry_reason_file}"
}
issue_mark_ready() {
  : >"${ready_flag}"
}
issue_after_reconciled() { :; }
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" && "${2:-}" == "repos/example/repo/issues/77/comments" ]]; then
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
  "$shared_bin/provider-cooldown-state.sh" \
  "$bin_dir/gh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_POSTED_COMMENT_FILE="$posted_comment_file" \
  bash "$SCRIPT" \
    --session fl-issue-77 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

grep -q '^schedule provider-quota-limit$' "$provider_log"
test "$(cat "$retry_reason_file")" = "provider-quota-limit"
test -f "$ready_flag"
grep -q '^STATUS=FAILED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
grep -q '^ACTION=host-comment-blocker$' <<<"$output"
grep -q '^FAILURE_REASON=provider-quota-limit$' <<<"$output"
test -f "$runs_root/fl-issue-77/issue-comment.md"
grep -q '^# Blocker: Provider quota is currently exhausted$' "$runs_root/fl-issue-77/issue-comment.md"
grep -q 'configured openclaw account hit a provider-side rate limit' "$runs_root/fl-issue-77/issue-comment.md"
test -f "$posted_comment_file"
grep -q '^# Blocker: Provider quota is currently exhausted$' "$posted_comment_file"

echo "issue reconcile provider cooldown scheduling test passed"
