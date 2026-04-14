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
state_root="$tmpdir/state"
bin_dir="$tmpdir/bin"
hook_file="$tmpdir/hooks.sh"
retry_reason_file="$tmpdir/retry-reason.txt"
blocked_file="$tmpdir/blocked.txt"
cleanup_file="$tmpdir/cleanup.txt"
gh_log="$tmpdir/gh.log"

mkdir -p "$shared_bin" "$runs_root/fl-pr-404" "$history_root" "$repo_root" "$bin_dir" "$state_root"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-pr-404/run.env" <<'EOF'
PR_NUMBER=404
SESSION=fl-pr-404
WORKTREE=/tmp/nonexistent-pr-worktree
STARTED_AT=2026-04-14T04:00:00Z
EOF

cat >"$runs_root/fl-pr-404/result.env" <<'EOF'
OUTCOME=approved-local-review-passed
ACTION=host-approve-and-merge
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-pr-404/run.env
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

cp "${FLOW_ROOT}/tools/bin/reconcile-bootstrap-lib.sh" "$shared_bin/reconcile-bootstrap-lib.sh"
cp "${FLOW_ROOT}/tools/bin/flow-config-lib.sh" "$shared_bin/flow-config-lib.sh"
cp "${FLOW_ROOT}/tools/bin/flow-shell-lib.sh" "$shared_bin/flow-shell-lib.sh"
cp "${FLOW_ROOT}/tools/bin/agent-project-retry-state" "$shared_bin/agent-project-retry-state"
cp "${FLOW_ROOT}/tools/bin/github-core-rate-limit-state.sh" "$shared_bin/github-core-rate-limit-state.sh"
cp "${FLOW_ROOT}/tools/bin/github-write-outbox.sh" "$shared_bin/github-write-outbox.sh"

cat >"$hook_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_automerge_allowed() { printf 'yes\n'; }
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
printf '%s\n' "$*" >>"${TEST_GH_LOG:?}"
echo "gh should not be called while GitHub core cooldown is active" >&2
exit 97
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/branch-verification-guard.sh" \
  "$shared_bin/reconcile-bootstrap-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/agent-project-retry-state" \
  "$shared_bin/github-core-rate-limit-state.sh" \
  "$shared_bin/github-write-outbox.sh" \
  "$hook_file" \
  "$bin_dir/gh"

ACP_STATE_ROOT="$state_root" \
ACP_RETRY_COOLDOWNS="300,900" \
bash "$shared_bin/github-core-rate-limit-state.sh" schedule "github-api-rate-limit" >/dev/null

output="$(
  PATH="$bin_dir:$PATH" \
  GH_TOKEN="test-token" \
  TEST_GH_LOG="$gh_log" \
  SHARED_AGENT_HOME="$shared_home" \
  ACP_STATE_ROOT="$state_root" \
  ACP_RETRY_COOLDOWNS="300,900" \
  AGENT_CONTROL_PLANE_ROOT="$FLOW_ROOT" \
  bash "$SCRIPT" \
    --session fl-pr-404 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

grep -q '^STATUS=FAILED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
grep -q '^ACTION=host-merge-rate-limit-retry$' <<<"$output"
grep -q '^FAILURE_REASON=github-api-rate-limit$' <<<"$output"
test -f "$retry_reason_file"
grep -q '^github-api-rate-limit$' "$retry_reason_file"
test -f "$blocked_file"
gh_call_count="0"
if [[ -f "$gh_log" ]]; then
  gh_call_count="$(wc -l <"$gh_log" | tr -d ' ')"
fi
test "$gh_call_count" = "0"
pending_file="$(find "$state_root/github-outbox/pending" -type f -name 'approval-*.json' | head -n 1)"
test -n "$pending_file"
jq -e '.type == "approval"' "$pending_file" >/dev/null
jq -e '.number == "404"' "$pending_file" >/dev/null

echo "pr reconcile skips host action while github core rate limited test passed"
