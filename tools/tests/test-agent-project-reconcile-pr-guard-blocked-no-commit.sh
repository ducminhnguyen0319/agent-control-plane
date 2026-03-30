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

mkdir -p "$shared_bin" "$runs_root/fl-pr-201" "$history_root" "$bin_dir"

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
git -C "$repo_root" checkout -b codex/pr-201-guard >/dev/null 2>&1
git -C "$repo_root" push origin codex/pr-201-guard >/dev/null 2>&1
branch_head="$(git -C "$repo_root" rev-parse HEAD)"

git clone "$origin_repo" "$pr_worktree" >/dev/null 2>&1
git -C "$pr_worktree" checkout codex/pr-201-guard >/dev/null 2>&1
printf 'hello guard\n' >"$pr_worktree/README.md"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=fl-pr-201\n'
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$runs_root/fl-pr-201/run.env"
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_bin/branch-verification-guard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >&2 <<'MSG'
Verification guard blocked branch publication.

Why it was blocked:
- changed test files were not covered by a targeted test command
MSG
exit 43
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

cat >"$runs_root/fl-pr-201/run.env" <<EOF
PR_NUMBER=201
WORKTREE=$pr_worktree
PR_HEAD_REF=codex/pr-201-guard
EOF

cat >"$runs_root/fl-pr-201/result.env" <<'EOF'
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
    --session fl-pr-201 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$pr_hook"
)"

test "$(cat "$pr_reason_file")" = "verification-guard-blocked"
test -f "$pr_blocked_file"
test -f "$runs_root/fl-pr-201/reconciled.ok"
grep -q '^STATUS=SUCCEEDED$' <<<"$pr_out"
grep -q '^OUTCOME=blocked$' <<<"$pr_out"
grep -q '^ACTION=host-verification-guard-blocked$' <<<"$pr_out"
grep -q '^FAILURE_REASON=verification-guard-blocked$' <<<"$pr_out"

test "$(git -C "$pr_worktree" rev-parse HEAD)" = "$branch_head"
grep -q '^ M README.md$' <<<"$(git -C "$pr_worktree" status --short)"
grep -q 'Verification guard blocked branch publication.' "$runs_root/fl-pr-201/host-blocker.md"

echo "agent-project reconcile PR guard-blocked no-commit test passed"
