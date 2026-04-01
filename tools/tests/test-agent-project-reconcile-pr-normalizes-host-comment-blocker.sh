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
retry_cleared_file="$tmpdir/retry-cleared.txt"
blocked_file="$tmpdir/blocked.txt"

mkdir -p "$shared_bin" "$runs_root/fl-pr-89" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-pr-89/run.env" <<'EOF'
PR_NUMBER=89
SESSION=fl-pr-89
WORKTREE=/tmp/nonexistent-pr-worktree
EOF

cat >"$runs_root/fl-pr-89/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-pr-89/run.env
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
pr_clear_retry() {
  : >"${retry_cleared_file}"
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
    --session fl-pr-89 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

test -f "$retry_cleared_file"
test -f "$blocked_file"
grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
grep -q '^ACTION=host-comment-pr-blocker$' <<<"$output"
grep -q '^RESULT_CONTRACT_NOTE=normalized-legacy-blocked-action$' <<<"$output"

echo "pr reconcile normalizes host-comment-blocker test passed"
