#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-reconcile-pr-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
shared_bin="$shared_home/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
bin_dir="$tmpdir/bin"
hook_file="$tmpdir/hooks.sh"
retry_reason_file="$tmpdir/retry-reason.txt"
blocked_file="$tmpdir/blocked.txt"
cleanup_file="$tmpdir/cleanup.txt"

mkdir -p "$shared_bin" "$runs_root/fl-pr-303" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-pr-303/run.env" <<'EOF'
PR_NUMBER=303
SESSION=fl-pr-303
WORKTREE=/tmp/nonexistent-pr-worktree
STARTED_AT=2026-04-02T21:00:00Z
EOF

cat >"$runs_root/fl-pr-303/result.env" <<'EOF'
OUTCOME=blocked
ACTION=requested-changes-or-blocked
EOF

cat >"$runs_root/fl-pr-303/pr-comment.md" <<'EOF'
## PR final review blocker

The changed component is dead code and does not affect the live admin support banner.
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-pr-303/run.env
OUT
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<EOF
#!/usr/bin/env bash
set -euo pipefail
: >"${cleanup_file}"
exit 0
EOF

cat >"$shared_bin/branch-verification-guard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$hook_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_schedule_retry() {
  printf '%s\n' "\$1" >"${retry_reason_file}"
}
pr_after_blocked() {
  : >"${blocked_file}"
}
pr_after_reconciled() { :; }
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  printf '{"state":"OPEN","baseRefName":"main","comments":[]}\n'
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  echo "gh: API rate limit exceeded for user ID 123. resets at 2026-04-03 01:20:43 CEST. (HTTP 403)" >&2
  exit 1
fi

exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/branch-verification-guard.sh" \
  "$hook_file" \
  "$bin_dir/gh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  bash "$SCRIPT" \
    --session fl-pr-303 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

grep -q '^STATUS=FAILED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
grep -q '^ACTION=host-comment-rate-limit-retry$' <<<"$output"
grep -q '^FAILURE_REASON=github-api-rate-limit$' <<<"$output"
test -f "$retry_reason_file"
grep -q '^github-api-rate-limit$' "$retry_reason_file"
test -f "$blocked_file"
test -f "$cleanup_file"
test -f "$runs_root/fl-pr-303/reconciled.ok"
grep -Fq '## Host action blocked' "$runs_root/fl-pr-303/pr-comment.md"
grep -Fq 'scheduled an automatic retry' "$runs_root/fl-pr-303/pr-comment.md"
test -f "$runs_root/fl-pr-303/host-github-rate-limit.log"
grep -Fq 'API rate limit exceeded' "$runs_root/fl-pr-303/host-github-rate-limit.log"

echo "pr reconcile retries host actions on github rate limit test passed"
