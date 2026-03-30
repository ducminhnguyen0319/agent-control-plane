#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PR_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-pr-session"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
bin_dir="$tmpdir/bin"
origin_repo="$tmpdir/origin.git"
repo_root="$tmpdir/repo-root"
pr_worktree="$tmpdir/pr-worktree"

mkdir -p "$shared_bin" "$runs_root/fl-pr-200" "$history_root" "$bin_dir"

cp "$PR_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-pr-session"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"

git init --bare "$origin_repo" >/dev/null 2>&1
git clone "$origin_repo" "$repo_root" >/dev/null 2>&1
printf 'hello\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$repo_root" branch -M main >/dev/null 2>&1
git -C "$repo_root" push origin main >/dev/null 2>&1
git -C "$repo_root" checkout -b codex/pr-200-noop >/dev/null 2>&1
git -C "$repo_root" push origin codex/pr-200-noop >/dev/null 2>&1

git clone "$origin_repo" "$pr_worktree" >/dev/null 2>&1
git -C "$pr_worktree" checkout codex/pr-200-noop >/dev/null 2>&1

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=fl-pr-200\n'
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$runs_root/fl-pr-200/run.env"
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

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  printf '{"state":"OPEN","baseRefName":"main"}\n'
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-pr-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/branch-verification-guard.sh" \
  "$bin_dir/gh"

cat >"$runs_root/fl-pr-200/run.env" <<EOF
PR_NUMBER=200
WORKTREE=$pr_worktree
PR_HEAD_REF=codex/pr-200-noop
EOF

cat >"$runs_root/fl-pr-200/result.env" <<'EOF'
OUTCOME=updated-branch
ACTION=host-push-pr-branch
EOF

pr_reason_file="$tmpdir/pr-retry-reason.txt"
pr_blocked_file="$tmpdir/pr-blocked.txt"
pr_hook="$tmpdir/pr-hook.sh"

cat >"$pr_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_schedule_retry() {
  printf '%s\n' "\$1" >"$pr_reason_file"
}
pr_after_blocked() {
  : >"$pr_blocked_file"
}
pr_after_reconciled() { :; }
EOF

chmod +x "$pr_hook"

pr_out="$(
  PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-200 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$pr_hook"
)"

test "$(cat "$pr_reason_file")" = "updated-branch-no-commits-ahead"
test -f "$pr_blocked_file"
grep -q '^STATUS=SUCCEEDED$' <<<"$pr_out"
grep -q '^OUTCOME=blocked$' <<<"$pr_out"
grep -q '^ACTION=host-noop-updated-branch$' <<<"$pr_out"
grep -q '^FAILURE_REASON=updated-branch-no-commits-ahead$' <<<"$pr_out"

echo "agent-project reconcile PR updated-branch noop test passed"
