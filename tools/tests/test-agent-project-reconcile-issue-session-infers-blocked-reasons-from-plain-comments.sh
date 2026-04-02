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

mkdir -p "$shared_bin" "$runs_root/fl-issue-901" "$runs_root/fl-issue-902" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-issue-901/run.env" <<'EOF'
ISSUE_ID=901
SESSION=fl-issue-901
WORKTREE=/tmp/mock-issue-901
EOF

cat >"$runs_root/fl-issue-901/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$runs_root/fl-issue-901/issue-comment.md" <<'EOF'
Target: payroll pay-period date-range validation
Why now: pay periods could be created or updated with an impossible start/end range.

Verification:
- PASS `pnpm --filter @f-losning/api test -- --runTestsByPath src/modules/payroll/payroll.service.spec.ts`
- PASS `git diff --check`
- BLOCKED `pnpm typecheck`

Blocker:
- `pnpm typecheck` fails in unrelated existing file `apps/api/src/modules/farm/scope-farm-checkin-code-uniqueness-migration.spec.ts`
EOF

cat >"$runs_root/fl-issue-902/run.env" <<'EOF'
ISSUE_ID=902
SESSION=fl-issue-902
WORKTREE=/tmp/mock-issue-902
EOF

cat >"$runs_root/fl-issue-902/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$runs_root/fl-issue-902/issue-comment.md" <<'EOF'
Blocked on external network access for the dependency-audit slice in issue #902.

What I completed this cycle:
- Reviewed the required package surfaces locally.
- Verified the current lockfile versions already present in the repo.

Additional notes:
- `pnpm audit` failed with `ENOTFOUND`.
- `gh issue view` failed to reach `api.github.com`.
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail

session=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --session) session="\${2:-}"; shift 2 ;;
    --runs-root) shift 2 ;;
    *) shift ;;
  esac
done

printf 'SESSION=%s\n' "\$session"
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s/%s/run.env\n' "$runs_root" "\$session"
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

cat >"$tmpdir/hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issue_schedule_retry() {
  printf '%s=%s\n' "${ISSUE_ID:-}" "$1" >>"${TEST_RETRY_REASONS_FILE:?}"
}
issue_mark_blocked() { :; }
issue_after_reconciled() { :; }
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/flow-resident-worker-lib.sh" \
  "$tmpdir/hooks.sh" \
  "$bin_dir/gh"

output_901="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_RETRY_REASONS_FILE="$tmpdir/retry-reasons.txt" \
  bash "$SCRIPT" \
    --session fl-issue-901 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hooks.sh"
)"

output_902="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_RETRY_REASONS_FILE="$tmpdir/retry-reasons.txt" \
  bash "$SCRIPT" \
    --session fl-issue-902 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hooks.sh"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$output_901"
grep -q '^FAILURE_REASON=verification-guard-blocked$' <<<"$output_901"
grep -q '^STATUS=SUCCEEDED$' <<<"$output_902"
grep -q '^FAILURE_REASON=external-network-access-blocked$' <<<"$output_902"
grep -q '^901=verification-guard-blocked$' "$tmpdir/retry-reasons.txt"
grep -q '^902=external-network-access-blocked$' "$tmpdir/retry-reasons.txt"

echo "issue reconcile infers blocked reasons from plain comments test passed"
