#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISSUE_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"
PR_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-pr-session"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
bin_dir="$tmpdir/bin"

mkdir -p \
  "$shared_bin" \
  "$shared_assets" \
  "$runs_root/fl-issue-321" \
  "$runs_root/fl-issue-scope-blocked" \
  "$runs_root/fl-issue-verification-blocked" \
  "$runs_root/fl-pr-77" \
  "$runs_root/fl-issue-invalid" \
  "$runs_root/fl-pr-invalid" \
  "$runs_root/fl-pr-running-merged" \
  "$history_root" \
  "$bin_dir"

cp "$ISSUE_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-issue-session"
cp "$PR_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-pr-session"
cp "$FLOW_ROOT/tools/bin/reconcile-bootstrap-lib.sh" "$shared_bin/reconcile-bootstrap-lib.sh"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$RESIDENT_LIB" "$shared_bin/flow-resident-worker-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail

session=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --session) session="\$2"; shift 2 ;;
    --runs-root) shift 2 ;;
    *) shift ;;
  esac
done

case "\$session" in
  fl-issue-321)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=FAILED\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-issue-321/run.env"
    printf 'FAILURE_REASON=auth-refresh-timeout\n'
    ;;
  fl-pr-77)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=FAILED\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-pr-77/run.env"
    printf 'FAILURE_REASON=resume-attempts-exhausted\n'
    ;;
  fl-issue-invalid)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=SUCCEEDED\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-issue-invalid/run.env"
    ;;
  fl-issue-scope-blocked)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=SUCCEEDED\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-issue-scope-blocked/run.env"
    ;;
  fl-issue-verification-blocked)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=SUCCEEDED\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-issue-verification-blocked/run.env"
    ;;
  fl-pr-invalid)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=SUCCEEDED\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-pr-invalid/run.env"
    ;;
  fl-pr-running-merged)
    printf 'SESSION=%s\n' "\$session"
    printf 'STATUS=RUNNING\n'
    printf 'META_FILE=%s\n' "$runs_root/fl-pr-running-merged/run.env"
    ;;
  *)
    echo "unexpected session: \$session" >&2
    exit 1
    ;;
esac
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_bin/branch-verification-guard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_bin/agent-project-publish-issue-pr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

session=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) session="$2"; shift 2 ;;
    *) shift ;;
  esac
done

case "$session" in
  fl-issue-scope-blocked)
    cat >&2 <<'MSG'
Scope guard blocked issue #330 from publishing as a single PR.

The branch is too broad for the current flow and should be split into a smaller slice before publish.
MSG
    exit 42
    ;;
  fl-issue-verification-blocked)
    cat >&2 <<'MSG'
Verification guard blocked branch publication.

Why it was blocked:
- missing API typecheck or repo typecheck for API changes
MSG
    exit 43
    ;;
  *)
    echo "unexpected publish session: $session" >&2
    exit 1
    ;;
esac
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  pr_number="${3:-}"
  case "$pr_number" in
    88)
      printf '{"state":"MERGED","baseRefName":"main"}\n'
      ;;
    *)
      printf '{"state":"OPEN","baseRefName":"main"}\n'
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  printf '5000\n'
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/agent-project-reconcile-pr-session" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/agent-project-publish-issue-pr" \
  "$shared_bin/branch-verification-guard.sh" \
  "$bin_dir/gh"

cat >"$runs_root/fl-issue-321/run.env" <<'EOF'
ISSUE_ID=321
WORKTREE=/tmp/mock-issue-worktree
EOF

cat >"$runs_root/fl-pr-77/run.env" <<'EOF'
PR_NUMBER=77
WORKTREE=/tmp/mock-pr-worktree
ISSUE_ID=321
EOF

cat >"$runs_root/fl-issue-invalid/run.env" <<'EOF'
ISSUE_ID=322
WORKTREE=/tmp/mock-issue-invalid-worktree
EOF

cat >"$runs_root/fl-issue-invalid/result.env" <<'EOF'
OUTCOME=implemented
ACTION=invalid-action
EOF

cat >"$runs_root/fl-issue-scope-blocked/run.env" <<'EOF'
ISSUE_ID=330
WORKTREE=/tmp/mock-issue-scope-blocked-worktree
EOF

cat >"$runs_root/fl-issue-scope-blocked/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

cat >"$runs_root/fl-issue-verification-blocked/run.env" <<'EOF'
ISSUE_ID=331
WORKTREE=/tmp/mock-issue-verification-blocked-worktree
EOF

cat >"$runs_root/fl-issue-verification-blocked/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

cat >"$runs_root/fl-pr-invalid/run.env" <<'EOF'
PR_NUMBER=78
WORKTREE=/tmp/mock-pr-invalid-worktree
EOF

cat >"$runs_root/fl-pr-invalid/result.env" <<'EOF'
OUTCOME=updated-branch
ACTION=invalid-action
EOF

cat >"$runs_root/fl-pr-running-merged/run.env" <<'EOF'
PR_NUMBER=88
WORKTREE=/tmp/mock-pr-running-merged-worktree
EOF

issue_reason_file="$tmpdir/issue-retry-reason.txt"
pr_reason_file="$tmpdir/pr-retry-reason.txt"
issue_invalid_reason_file="$tmpdir/issue-invalid-retry-reason.txt"
pr_invalid_reason_file="$tmpdir/pr-invalid-retry-reason.txt"
issue_scope_retry_reason_file="$tmpdir/issue-scope-retry-reason.txt"
issue_scope_clear_file="$tmpdir/issue-scope-clear.txt"
issue_scope_blocked_file="$tmpdir/issue-scope-blocked.txt"
issue_verification_retry_reason_file="$tmpdir/issue-verification-retry-reason.txt"
issue_verification_clear_file="$tmpdir/issue-verification-clear.txt"
issue_verification_blocked_file="$tmpdir/issue-verification-blocked.txt"
issue_hook="$tmpdir/issue-hook.sh"
pr_hook="$tmpdir/pr-hook.sh"
issue_invalid_hook="$tmpdir/issue-invalid-hook.sh"
pr_invalid_hook="$tmpdir/pr-invalid-hook.sh"
issue_scope_hook="$tmpdir/issue-scope-hook.sh"
issue_verification_hook="$tmpdir/issue-verification-hook.sh"
pr_merged_hook="$tmpdir/pr-merged-hook.sh"

cat >"$issue_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() {
  printf '%s\n' "\$1" >"$issue_reason_file"
}
issue_mark_ready() { :; }
issue_after_reconciled() { :; }
EOF

cat >"$pr_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_schedule_retry() {
  printf '%s\n' "\$1" >"$pr_reason_file"
}
pr_after_failed() { :; }
pr_after_reconciled() { :; }
EOF

cat >"$issue_invalid_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() {
  printf '%s\n' "\$1" >"$issue_invalid_reason_file"
}
issue_mark_ready() { :; }
issue_after_reconciled() { :; }
EOF

cat >"$issue_scope_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() {
  printf '%s\n' "\$1" >"$issue_scope_retry_reason_file"
}
issue_clear_retry() {
  : >"$issue_scope_clear_file"
}
issue_mark_blocked() {
  : >"$issue_scope_blocked_file"
}
issue_after_reconciled() { :; }
EOF

cat >"$issue_verification_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() {
  printf '%s\n' "\$1" >"$issue_verification_retry_reason_file"
}
issue_clear_retry() {
  : >"$issue_verification_clear_file"
}
issue_mark_blocked() {
  : >"$issue_verification_blocked_file"
}
issue_after_reconciled() { :; }
EOF

cat >"$pr_invalid_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_schedule_retry() {
  printf '%s\n' "\$1" >"$pr_invalid_reason_file"
}
pr_after_failed() { :; }
pr_after_reconciled() { :; }
EOF

cat >"$pr_merged_hook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pr_clear_retry() { :; }
pr_cleanup_merged_residue() { :; }
pr_after_merged() { :; }
pr_after_reconciled() { :; }
EOF

chmod +x "$issue_hook" "$pr_hook" "$issue_invalid_hook" "$pr_invalid_hook" "$issue_scope_hook" "$issue_verification_hook" "$pr_merged_hook"
repo_slug="example-owner/alpha"

issue_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session fl-issue-321 \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$issue_hook"
)"
test "$(cat "$issue_reason_file")" = "auth-refresh-timeout"
grep -q '^FAILURE_REASON=auth-refresh-timeout$' <<<"$issue_out"

pr_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-77 \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$pr_hook"
)"
test "$(cat "$pr_reason_file")" = "resume-attempts-exhausted"
grep -q '^FAILURE_REASON=resume-attempts-exhausted$' <<<"$pr_out"

issue_invalid_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session fl-issue-invalid \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$issue_invalid_hook"
)"
test "$(cat "$issue_invalid_reason_file")" = "invalid-result-contract"
grep -q '^STATUS=FAILED$' <<<"$issue_invalid_out"
grep -q '^OUTCOME=invalid-contract$' <<<"$issue_invalid_out"
grep -q '^ACTION=queued-issue-retry$' <<<"$issue_invalid_out"
grep -q '^FAILURE_REASON=invalid-result-contract$' <<<"$issue_invalid_out"
grep -q '^RESULT_CONTRACT_NOTE=invalid-result-contract$' <<<"$issue_invalid_out"

issue_scope_blocked_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session fl-issue-scope-blocked \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$issue_scope_hook"
)"
test ! -f "$issue_scope_clear_file"
test -f "$issue_scope_blocked_file"
test "$(cat "$issue_scope_retry_reason_file")" = "scope-guard-blocked"
grep -q '^STATUS=SUCCEEDED$' <<<"$issue_scope_blocked_out"
grep -q '^OUTCOME=blocked$' <<<"$issue_scope_blocked_out"
grep -q '^ACTION=host-comment-blocker$' <<<"$issue_scope_blocked_out"
grep -q '^FAILURE_REASON=scope-guard-blocked$' <<<"$issue_scope_blocked_out"
grep -q '^PUBLISH_ERROR=Scope guard blocked issue #330 from publishing as a single PR\.' <<<"$issue_scope_blocked_out"

issue_verification_blocked_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session fl-issue-verification-blocked \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$issue_verification_hook"
)"
test ! -f "$issue_verification_clear_file"
test -f "$issue_verification_blocked_file"
test "$(cat "$issue_verification_retry_reason_file")" = "verification-guard-blocked"
grep -q '^STATUS=SUCCEEDED$' <<<"$issue_verification_blocked_out"
grep -q '^OUTCOME=blocked$' <<<"$issue_verification_blocked_out"
grep -q '^ACTION=host-comment-blocker$' <<<"$issue_verification_blocked_out"
grep -q '^FAILURE_REASON=verification-guard-blocked$' <<<"$issue_verification_blocked_out"
grep -q '^PUBLISH_ERROR=Verification guard blocked branch publication\.' <<<"$issue_verification_blocked_out"

pr_invalid_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-invalid \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$pr_invalid_hook"
)"
test "$(cat "$pr_invalid_reason_file")" = "invalid-result-contract"
grep -q '^STATUS=FAILED$' <<<"$pr_invalid_out"
grep -q '^OUTCOME=invalid-contract$' <<<"$pr_invalid_out"
grep -q '^ACTION=queued-pr-retry$' <<<"$pr_invalid_out"
grep -q '^FAILURE_REASON=invalid-result-contract$' <<<"$pr_invalid_out"
grep -q '^RESULT_CONTRACT_NOTE=invalid-result-contract$' <<<"$pr_invalid_out"

pr_merged_running_out="$(
  PATH="$bin_dir:$PATH" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-running-merged \
    --repo-slug "$repo_slug" \
    --repo-root /tmp/mock-repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$pr_merged_hook"
)"
grep -q '^STATUS=SUCCEEDED$' <<<"$pr_merged_running_out"
grep -q '^PR_STATE=MERGED$' <<<"$pr_merged_running_out"
grep -q '^OUTCOME=merged$' <<<"$pr_merged_running_out"
grep -q '^ACTION=approved-and-merged$' <<<"$pr_merged_running_out"
if grep -q '^FAILURE_REASON=' <<<"$pr_merged_running_out"; then
  echo "unexpected FAILURE_REASON for merged PR cleanup" >&2
  printf '%s\n' "$pr_merged_running_out" >&2
  exit 1
fi

echo "agent-project reconcile failure reason test passed"
