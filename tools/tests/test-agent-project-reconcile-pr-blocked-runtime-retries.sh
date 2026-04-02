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
failed_file="$tmpdir/failed.txt"

mkdir -p "$shared_bin" "$runs_root/fl-pr-91" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-pr-91/run.env" <<'EOF'
PR_NUMBER=91
SESSION=fl-pr-91
WORKTREE=/tmp/nonexistent-pr-worktree
EOF

cat >"$runs_root/fl-pr-91/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-pr-blocker
DETAIL=worker-tool-exec-empty-command
EOF

cat >"$runs_root/fl-pr-91/fl-pr-91.log" <<'EOF'
[tools] exec failed: Provide a command to start.
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-pr-91/run.env
OUT
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

cat >"$hook_file" <<EOF
pr_schedule_retry() {
  printf '%s\n' "\$1" >"${retry_reason_file}"
}
pr_after_failed() {
  : >"${failed_file}"
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
  printf '{}\n'
  exit 0
fi
exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/branch-verification-guard.sh" \
  "$bin_dir/gh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  bash "$SCRIPT" \
    --session fl-pr-91 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

test -f "$retry_reason_file"
test -f "$failed_file"
grep -q '^worker-tool-exec-empty-command$' "$retry_reason_file"
grep -q '^STATUS=FAILED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
grep -q '^ACTION=queued-pr-retry$' <<<"$output"
grep -q '^FAILURE_REASON=worker-tool-exec-empty-command$' <<<"$output"

echo "pr reconcile retries blocked runtime failures test passed"
