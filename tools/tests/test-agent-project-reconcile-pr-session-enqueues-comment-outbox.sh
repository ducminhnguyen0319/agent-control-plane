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

mkdir -p "$shared_bin" "$runs_root/fl-pr-505" "$history_root" "$repo_root" "$bin_dir" "$state_root"
git -C "$repo_root" init -b main >/dev/null 2>&1

cat >"$runs_root/fl-pr-505/run.env" <<'EOF'
PR_NUMBER=505
SESSION=fl-pr-505
WORKTREE=/tmp/nonexistent-pr-worktree
STARTED_AT=2026-04-14T06:00:00Z
EOF

cat >"$runs_root/fl-pr-505/result.env" <<'EOF'
OUTCOME=blocked
ACTION=requested-changes-or-blocked
EOF

cat >"$runs_root/fl-pr-505/pr-comment.md" <<'EOF'
## PR final review blocker

Queued locally while GitHub write access is unavailable.
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-pr-505/run.env
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

cp "${FLOW_ROOT}/tools/bin/reconcile-bootstrap-lib.sh" "$shared_bin/reconcile-bootstrap-lib.sh"
cp "${FLOW_ROOT}/tools/bin/flow-config-lib.sh" "$shared_bin/flow-config-lib.sh"
cp "${FLOW_ROOT}/tools/bin/flow-shell-lib.sh" "$shared_bin/flow-shell-lib.sh"
cp "${FLOW_ROOT}/tools/bin/github-write-outbox.sh" "$shared_bin/github-write-outbox.sh"

cat >"$hook_file" <<EOF
#!/usr/bin/env bash
set -euo pipefail
pr_schedule_retry() {
  printf '%s\n' "\$1" >"${retry_reason_file}"
}
pr_clear_retry() { :; }
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
  echo "temporary network failure" >&2
  exit 1
fi

exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/branch-verification-guard.sh" \
  "$shared_bin/reconcile-bootstrap-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/github-write-outbox.sh" \
  "$hook_file" \
  "$bin_dir/gh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  ACP_STATE_ROOT="$state_root" \
  F_LOSNING_STATE_ROOT="$state_root" \
  FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
  bash "$SCRIPT" \
    --session fl-pr-505 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^OUTCOME=blocked$' <<<"$output"
test -f "$blocked_file"
if [[ -f "$retry_reason_file" ]]; then
  echo "PR comment outbox path should not schedule a retry" >&2
  exit 1
fi

pending_file="$(find "$state_root/github-outbox/pending" -type f -name '*.json' | head -n 1)"
test -n "$pending_file"
jq -e '.type == "comment"' "$pending_file" >/dev/null
jq -e '.kind == "pr"' "$pending_file" >/dev/null
jq -e '.number == "505"' "$pending_file" >/dev/null
jq -e '.body | contains("Queued locally while GitHub write access is unavailable.")' "$pending_file" >/dev/null

echo "agent-project-reconcile-pr-session enqueues comment outbox test passed"
