#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PR_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-pr-session"
RECORD_VERIFICATION_SRC="${FLOW_ROOT}/tools/bin/record-verification.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
flow_tools_dir="$tmpdir/flow-tools"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
bin_dir="$tmpdir/bin"
node_bin_dir="$(dirname "$(command -v node)")"
origin_repo="$tmpdir/origin.git"
repo_root="$tmpdir/repo-root"
pr_worktree="$tmpdir/pr-worktree"
posted_comment_file="$tmpdir/posted-comment.md"

mkdir -p "$shared_bin" "$shared_assets" "$flow_tools_dir" "$runs_root/fl-pr-202" "$history_root" "$bin_dir"

cp "$PR_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-pr-session"
cp "$RECORD_VERIFICATION_SRC" "$flow_tools_dir/record-verification.sh"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

git init --bare "$origin_repo" >/dev/null 2>&1
git clone "$origin_repo" "$repo_root" >/dev/null 2>&1
mkdir -p "$repo_root/scripts"
cat >"$repo_root/README.md" <<'EOF'
hello
EOF
cat >"$repo_root/scripts/host-playwright-retry.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "host verification ok"
EOF
chmod +x "$repo_root/scripts/host-playwright-retry.sh"
git -C "$repo_root" add README.md scripts/host-playwright-retry.sh
git -C "$repo_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$repo_root" branch -M main >/dev/null 2>&1
git -C "$repo_root" push origin main >/dev/null 2>&1
git -C "$repo_root" checkout -b codex/pr-202-recovery >/dev/null 2>&1
git -C "$repo_root" push origin codex/pr-202-recovery >/dev/null 2>&1

git clone "$origin_repo" "$pr_worktree" >/dev/null 2>&1
git -C "$pr_worktree" checkout codex/pr-202-recovery >/dev/null 2>&1
git -C "$pr_worktree" config user.name Test
git -C "$pr_worktree" config user.email test@example.com
branch_head="$(git -C "$pr_worktree" rev-parse HEAD)"
cat >"$pr_worktree/README.md" <<'EOF'
hello recovered
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=fl-pr-202\n'
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$runs_root/fl-pr-202/run.env"
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_bin/branch-verification-guard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

run_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) run_dir="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -f "${run_dir}/verification.jsonl" ]] && grep -Fq 'bash scripts/host-playwright-retry.sh' "${run_dir}/verification.jsonl"; then
  printf 'VERIFICATION_GUARD_STATUS=ok\n'
  exit 0
fi

cat >&2 <<'MSG'
Verification guard blocked branch publication.

Why it was blocked:
- changed test files were not covered by a targeted test command
MSG
exit 43
EOF

cat >"$bin_dir/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "pr" && "\${2:-}" == "view" ]]; then
  if [[ " \$* " == *" --json comments "* ]]; then
    printf '{"comments":[]}\n'
  else
    printf '{"state":"OPEN","baseRefName":"main"}\n'
  fi
  exit 0
fi

if [[ "\${1:-}" == "api" && "\${2:-}" == "repos/example/repo/issues/202/comments" ]]; then
  shift 2
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      -f)
        if [[ "\${2:-}" == body=* ]]; then
          printf '%s' "\${2#body=}" >"$posted_comment_file"
        fi
        shift 2
        ;;
      --method)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  exit 0
fi

echo "unexpected gh invocation: \$*" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-pr-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/branch-verification-guard.sh" \
  "$flow_tools_dir/record-verification.sh" \
  "$bin_dir/gh"

cat >"$runs_root/fl-pr-202/run.env" <<EOF
PR_NUMBER=202
WORKTREE=$pr_worktree
PR_HEAD_REF=codex/pr-202-recovery
FLOW_TOOLS_DIR=$flow_tools_dir
EOF

cat >"$runs_root/fl-pr-202/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-pr-blocker
EOF

cat >"$runs_root/fl-pr-202/prompt.md" <<'EOF'
Pre-approved local verification fallbacks:
- apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts | loopback retry command: `bash scripts/host-playwright-retry.sh`
EOF

cat >"$runs_root/fl-pr-202/pr-comment.md" <<'EOF'
**Summary**
- Updated tenant go-live runbook.

**Verification**
- ✅ `pnpm --filter @alpha/api test -- --testPathPatterns="auth.service.extended"`
- ❌ `bash scripts/with-test-namespace.sh pnpm --filter @alpha/web exec playwright test e2e/archive/auth/tenant-isolation-login.spec.ts --project=chromium` (Next dev failed: `listen EPERM 0.0.0.0:3000`)

**Blocker**
- Required Playwright coverage could not run because the web server failed to bind to local ports.
EOF

cat >"$runs_root/fl-pr-202/fl-pr-202.log" <<'EOF'
Error: listen EPERM: operation not permitted 127.0.0.1:3001
EOF

cat >"$runs_root/fl-pr-202/verification.jsonl" <<'EOF'
{"timestamp":"2026-03-17T14:22:19.125Z","status":"pass","command":"pnpm --filter @alpha/api test -- --testPathPatterns=\"auth.service.extended\""}
EOF

pr_retry_reason_file="$tmpdir/pr-retry-reason.txt"
pr_retry_cleared_file="$tmpdir/pr-retry-cleared.txt"
pr_updated_file="$tmpdir/pr-updated.txt"
pr_hook="$tmpdir/pr-hook.sh"

cat >"$pr_hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_schedule_retry() {
  printf '%s\n' "\$1" >"$pr_retry_reason_file"
}
pr_clear_retry() {
  : >"$pr_retry_cleared_file"
}
pr_after_updated_branch() {
  : >"$pr_updated_file"
}
pr_after_reconciled() { :; }
EOF

chmod +x "$pr_hook"

pr_out="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-202 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$pr_hook"
)"

test -f "$pr_retry_cleared_file"
test -f "$pr_updated_file"
test -f "$runs_root/fl-pr-202/reconciled.ok"
grep -q '^STATUS=SUCCEEDED$' <<<"$pr_out"
grep -q '^OUTCOME=updated-branch$' <<<"$pr_out"
grep -q '^ACTION=host-push-pr-branch$' <<<"$pr_out"
grep -q '^RESULT_CONTRACT_NOTE=host-recovered-sandbox-bind-failure$' <<<"$pr_out"

grep -Fq 'bash scripts/host-playwright-retry.sh' "$runs_root/fl-pr-202/verification.jsonl"
grep -Fq 'host-recovery-after-sandbox-bind-failure' "$runs_root/fl-pr-202/verification.jsonl"
grep -Fq '**Host Recovery**' "$runs_root/fl-pr-202/pr-comment.md"
if grep -Fq '**Blocker**' "$runs_root/fl-pr-202/pr-comment.md"; then
  echo "blocker section should be removed after host recovery" >&2
  exit 1
fi
grep -Fq 'bash scripts/host-playwright-retry.sh' "$posted_comment_file"
grep -q '^OUTCOME=updated-branch$' "$runs_root/fl-pr-202/result.env"

remote_head="$(git --git-dir="$origin_repo" rev-parse refs/heads/codex/pr-202-recovery)"
test "$remote_head" != "$branch_head"
test "$(git --git-dir="$origin_repo" show "${remote_head}:README.md")" = "hello recovered"

echo "agent-project reconcile PR blocked host recovery test passed"
