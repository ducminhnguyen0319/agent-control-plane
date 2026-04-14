#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISSUE_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
OUTBOX_BIN="${FLOW_ROOT}/tools/bin/github-write-outbox.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
state_root="$tmpdir/state"
bin_dir="$tmpdir/bin"
output_file="$tmpdir/output.txt"

mkdir -p \
  "$shared_bin" \
  "$shared_assets" \
  "$runs_root/demo-issue-901" \
  "$history_root" \
  "$repo_root" \
  "$state_root" \
  "$bin_dir"

cp "$ISSUE_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-issue-session"
cp "$FLOW_ROOT/tools/bin/reconcile-bootstrap-lib.sh" "$shared_bin/reconcile-bootstrap-lib.sh"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$RESIDENT_LIB" "$shared_bin/flow-resident-worker-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
cp "$OUTBOX_BIN" "$shared_bin/github-write-outbox.sh"
cp "$FLOW_ROOT/tools/bin/agent-github-update-labels" "$shared_bin/agent-github-update-labels"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=demo-issue-901\n'
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$runs_root/demo-issue-901/run.env"
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'CLEANUP_STATUS=0\n'
printf 'CLEANUP_MODE=branch\n'
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh unavailable during test" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/reconcile-bootstrap-lib.sh" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-resident-worker-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/github-write-outbox.sh" \
  "$shared_bin/agent-github-update-labels" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$bin_dir/gh"

cat >"$runs_root/demo-issue-901/run.env" <<'EOF'
ISSUE_ID=901
WORKTREE=/tmp/mock-issue-worktree
BRANCH=agent/demo/issue-901
EOF

cat >"$runs_root/demo-issue-901/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
DETAIL=worker-exit-failed
EOF

cat >"$runs_root/demo-issue-901/issue-comment.md" <<'EOF'
# Blocker: Worker produced no publishable delta
EOF

cat >"$tmpdir/issue-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issue_before_success() { :; }
issue_before_blocked() { :; }
issue_schedule_retry() { :; }
issue_mark_ready() { :; }
issue_clear_retry() { :; }
issue_remove_running() { :; }
issue_mark_blocked() { :; }
issue_should_close_as_superseded() { return 1; }
issue_close_as_superseded() { :; }
issue_after_pr_created() { :; }
issue_after_reconciled() { :; }
issue_publish_extra_args() { :; }
EOF
chmod +x "$tmpdir/issue-hook.sh"

PATH="$bin_dir:$PATH" \
SHARED_AGENT_HOME="$shared_agent_home" \
ACP_STATE_ROOT="$state_root" \
F_LOSNING_STATE_ROOT="$state_root" \
FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no" \
bash "$shared_bin/agent-project-reconcile-issue-session" \
  --session demo-issue-901 \
  --repo-slug example/demo \
  --repo-root "$repo_root" \
  --runs-root "$runs_root" \
  --history-root "$history_root" \
  --hook-file "$tmpdir/issue-hook.sh" >"$output_file"

grep -q '^STATUS=SUCCEEDED$' "$output_file"

pending_file="$(find "$state_root/github-outbox/pending" -type f -name '*.json' | head -n 1)"
test -n "$pending_file"
jq -e '.type == "comment"' "$pending_file" >/dev/null
jq -e '.kind == "issue"' "$pending_file" >/dev/null
jq -e '.number == "901"' "$pending_file" >/dev/null
jq -e '.body == "# Blocker: Worker produced no publishable delta"' "$pending_file" >/dev/null

echo "agent-project-reconcile-issue-session enqueues comment outbox test passed"
