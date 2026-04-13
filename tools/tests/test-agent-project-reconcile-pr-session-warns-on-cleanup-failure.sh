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
output_file="$tmpdir/output.txt"
stderr_file="$tmpdir/stderr.txt"

mkdir -p "$shared_bin" "$runs_root/fl-pr-77" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-pr-77/run.env" <<'EOF'
PR_NUMBER=77
SESSION=fl-pr-77
CODING_WORKER=claude
CLAUDE_MODEL=sonnet
WORKTREE=/tmp/mock-pr-worktree
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=FAILED
FAILURE_REASON=provider-quota-limit
META_FILE=${runs_root}/fl-pr-77/run.env
OUT
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'CLEANUP_STATUS=23\n'
printf 'CLEANUP_MODE=branch\n'
printf 'CLEANUP_ERROR=unable to prune worktree\n'
exit 23
EOF

cat >"$shared_bin/provider-cooldown-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'READY=no\n'
EOF

cat >"$shared_bin/branch-verification-guard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$hook_file" <<'EOF'
pr_schedule_retry() { :; }
pr_after_failed() { :; }
pr_after_reconciled() { :; }
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  printf '{"state":"OPEN","baseRefName":"main"}\n'
  exit 0
fi
exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/provider-cooldown-state.sh" \
  "$shared_bin/branch-verification-guard.sh" \
  "$bin_dir/gh"

PATH="$bin_dir:$PATH" \
SHARED_AGENT_HOME="$shared_home" \
bash "$SCRIPT" \
  --session fl-pr-77 \
  --repo-slug example/repo \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --hook-file "$hook_file" >"$output_file" 2>"$stderr_file"

grep -q '^STATUS=FAILED$' "$output_file"
grep -q 'pr cleanup warning session=fl-pr-77 status=23 mode=branch' "$stderr_file"
grep -q 'pr cleanup detail session=fl-pr-77 unable to prune worktree' "$stderr_file"

echo "agent-project-reconcile-pr-session warns on cleanup failure test passed"
