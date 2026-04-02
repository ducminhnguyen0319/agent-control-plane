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

mkdir -p "$shared_bin" "$runs_root/fl-issue-901" "$runs_root/fl-issue-902" "$runs_root/fl-issue-903" "$history_root" "$repo_root" "$bin_dir"
mkdir -p "$runs_root/fl-issue-904" "$runs_root/fl-issue-905"
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

cat >"$runs_root/fl-issue-903/run.env" <<'EOF'
ISSUE_ID=903
SESSION=fl-issue-903
WORKTREE=/tmp/mock-issue-903
EOF

cat >"$runs_root/fl-issue-903/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$runs_root/fl-issue-903/issue-comment.md" <<'EOF'
# Blocker: Localization requirements were not satisfied

Host publication stopped this cycle because the branch updated locale resources but still left obvious hardcoded user-facing strings in the touched UI files.
EOF

cat >"$runs_root/fl-issue-904/run.env" <<'EOF'
ISSUE_ID=904
SESSION=fl-issue-904
WORKTREE=/tmp/mock-issue-904
EOF

cat >"$runs_root/fl-issue-904/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$runs_root/fl-issue-904/issue-comment.md" <<'EOF'
Target: payroll pay-period reprocessing lock semantics
Why now: returning false-success for locked pay periods risks misleading operators.

Implemented locally but blocked from commit because the required repo-wide verification command `pnpm test` is currently failing outside this payroll slice.

Local payroll change prepared:
- reject reprocessing for locked `PROCESSED`/`PAID` pay periods

Verification run:
- PASS `pnpm --filter @f-losning/api test -- --runInBand src/modules/payroll/payroll.service.spec.ts`
- FAIL `pnpm test`

The payroll slice is ready once the baseline test failures above are resolved or explicitly waived.
EOF

cat >"$runs_root/fl-issue-905/run.env" <<'EOF'
ISSUE_ID=905
SESSION=fl-issue-905
WORKTREE=/tmp/mock-issue-905
EOF

cat >"$runs_root/fl-issue-905/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
EOF

cat >"$runs_root/fl-issue-905/issue-comment.md" <<'EOF'
Blocked on 2026-04-02 while running the first attendance TAP monitoring cycle for issue #905.

Blocker
- The direct cycle runner cannot access local infrastructure from this sandbox.
- Exact failing command:
  - `pnpm --filter @f-losning/api exec ts-node -r tsconfig-paths/register test/performance/run-attendance-check-in-monitoring-cycle.ts`
- The run fails with local socket connection errors (`AggregateError`, and earlier Redis attempts failed with `connect EPERM 127.0.0.1:6379`).
- Because the worker cannot reach the local Postgres/Redis services, I could not produce a truthful endpoint-latency baseline for this cycle.
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

output_903="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_RETRY_REASONS_FILE="$tmpdir/retry-reasons.txt" \
  bash "$SCRIPT" \
    --session fl-issue-903 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hooks.sh"
)"

output_904="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_RETRY_REASONS_FILE="$tmpdir/retry-reasons.txt" \
  bash "$SCRIPT" \
    --session fl-issue-904 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/hooks.sh"
)"

output_905="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  TEST_RETRY_REASONS_FILE="$tmpdir/retry-reasons.txt" \
  bash "$SCRIPT" \
    --session fl-issue-905 \
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
grep -q '^STATUS=SUCCEEDED$' <<<"$output_903"
grep -q '^FAILURE_REASON=localization-guard-blocked$' <<<"$output_903"
grep -q '^STATUS=SUCCEEDED$' <<<"$output_904"
grep -q '^FAILURE_REASON=verification-guard-blocked$' <<<"$output_904"
grep -q '^STATUS=SUCCEEDED$' <<<"$output_905"
grep -q '^FAILURE_REASON=worker-environment-blocked$' <<<"$output_905"
grep -q '^901=verification-guard-blocked$' "$tmpdir/retry-reasons.txt"
grep -q '^902=external-network-access-blocked$' "$tmpdir/retry-reasons.txt"
grep -q '^903=localization-guard-blocked$' "$tmpdir/retry-reasons.txt"
grep -q '^904=verification-guard-blocked$' "$tmpdir/retry-reasons.txt"
grep -q '^905=worker-environment-blocked$' "$tmpdir/retry-reasons.txt"

echo "issue reconcile infers blocked reasons from plain comments test passed"
