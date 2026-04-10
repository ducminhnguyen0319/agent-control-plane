#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISSUE_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
bin_dir="$tmpdir/bin"

mkdir -p \
  "$shared_bin" \
  "$shared_assets" \
  "$runs_root/demo-issue-321" \
  "$history_root" \
  "$repo_root" \
  "$bin_dir"

cp "$ISSUE_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-issue-session"
cp "$FLOW_ROOT/tools/bin/reconcile-bootstrap-lib.sh" "$shared_bin/reconcile-bootstrap-lib.sh"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$RESIDENT_LIB" "$shared_bin/flow-resident-worker-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=demo-issue-321\n'
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$runs_root/demo-issue-321/run.env"
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'CLEANUP=ok\n'
EOF

cat >"$shared_bin/agent-project-publish-issue-pr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'PR_NUMBER=12\n'
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" ]]; then
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/agent-project-publish-issue-pr" \
  "$bin_dir/gh"

cat >"$runs_root/demo-issue-321/run.env" <<'EOF'
ISSUE_ID=321
WORKTREE=/tmp/mock-issue-worktree
BRANCH=agent/demo/issue-321
EOF

cat >"$runs_root/demo-issue-321/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

cat >"$runs_root/demo-issue-321/runner.env" <<'EOF'
RUNNER_STATE=running
THREAD_ID=thread-demo-321
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=
LAST_FAILURE_REASON=
LAST_TRIGGER_REASON=
AUTH_WAIT_STARTED_AT=
LAST_AUTH_FINGERPRINT=
UPDATED_AT=2026-03-27T00:00:00Z
EOF

cat >"$tmpdir/issue-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issue_before_success() { :; }
issue_clear_retry() { :; }
issue_remove_running() { :; }
issue_after_pr_created() { :; }
issue_after_reconciled() { :; }
issue_publish_extra_args() { :; }
EOF
chmod +x "$tmpdir/issue-hook.sh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session demo-issue-321 \
    --repo-slug example/demo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$tmpdir/issue-hook.sh"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^RUNNER_STATE=succeeded$' "$runs_root/demo-issue-321/runner.env"
grep -q '^LAST_EXIT_CODE=0$' "$runs_root/demo-issue-321/runner.env"
grep -q '^LAST_FAILURE_REASON=' "$runs_root/demo-issue-321/runner.env"

echo "agent-project reconcile issue session normalizes runner state test passed"
