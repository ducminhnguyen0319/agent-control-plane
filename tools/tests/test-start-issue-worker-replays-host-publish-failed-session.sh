#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_WORKER="${FLOW_ROOT}/tools/bin/start-issue-worker.sh"
REAL_POLICY_BIN="${FLOW_ROOT}/tools/bin/issue-requires-local-workspace-install.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace="$tmpdir/workspace"
bin_dir="$workspace/bin"
templates_dir="$workspace/templates"
shim_dir="$tmpdir/shim"
agent_root="$tmpdir/agent"
history_root="$agent_root/history"
capture_dir="$tmpdir/capture"
session="alpha-issue-613"

mkdir -p "$bin_dir" "$templates_dir" "$shim_dir" "$agent_root" "$history_root" "$capture_dir"
ln -s "$REAL_WORKER" "$bin_dir/start-issue-worker.sh"
ln -s "$REAL_POLICY_BIN" "$bin_dir/issue-requires-local-workspace-install.sh"
ln -s "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
ln -s "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
ln -s "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"

cat >"$templates_dir/issue-prompt-template.md" <<'EOF'
Issue {ISSUE_ID}: {ISSUE_TITLE}
EOF

cat >"$templates_dir/scheduled-issue-prompt-template.md" <<'EOF'
Scheduled issue {ISSUE_ID}: {ISSUE_TITLE}
EOF

cat >"$shim_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$shim_dir/tmux"

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Issue ${issue_id}","body":"Retry host publish only.","url":"https://example.test/issues/${issue_id}","labels":[],"comments":[]}
JSON
  exit 0
fi
exit 64
EOF
chmod +x "$shim_dir/gh"

cat >"$bin_dir/retry-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'OUT'
KIND=issue
ITEM_ID=613
ATTEMPTS=4
NEXT_ATTEMPT_EPOCH=1775124428
NEXT_ATTEMPT_AT=2026-04-02T10:07:08Z
LAST_REASON=host-publish-failed
UPDATED_AT=2026-04-02T09:07:08Z
OUT
EOF
chmod +x "$bin_dir/retry-state.sh"

cat >"$bin_dir/reconcile-issue-worker.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${1:?session required}" >"${TEST_CAPTURE_DIR:?}/reconcile-session.txt"
cat <<'OUT'
STATUS=SUCCEEDED
ISSUE_ID=613
PR_NUMBER=99
OUTCOME=implemented
ACTION=host-publish-issue-pr
OUT
EOF
chmod +x "$bin_dir/reconcile-issue-worker.sh"

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected codex launch" >"${TEST_CAPTURE_DIR:?}/run-codex-safe.txt"
exit 99
EOF
chmod +x "$bin_dir/run-codex-safe.sh"

cat >"$bin_dir/new-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected worktree creation" >"${TEST_CAPTURE_DIR:?}/new-worktree.txt"
exit 98
EOF
chmod +x "$bin_dir/new-worktree.sh"

archive_dir="$history_root/${session}-20260402-110711"
mkdir -p "$archive_dir"
cat >"$archive_dir/run.env" <<'EOF'
ISSUE_ID=613
BRANCH=agent/alpha/issue-613-test
WORKTREE=/tmp/missing-worktree
EOF
cat >"$archive_dir/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
EOF
cat >"$archive_dir/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
ISSUE_ID=613
EOF

TEST_CAPTURE_DIR="$capture_dir" \
ACP_ROOT="$FLOW_ROOT" \
ACP_PROJECT_ID="alpha" \
ACP_AGENT_ROOT="$agent_root" \
ACP_RUNS_ROOT="$agent_root/runs" \
ACP_HISTORY_ROOT="$history_root" \
PATH="$shim_dir:$PATH" \
bash "$bin_dir/start-issue-worker.sh" 613 >/dev/null

test "$(cat "$capture_dir/reconcile-session.txt")" = "$session"
test ! -f "$capture_dir/run-codex-safe.txt"
test ! -f "$capture_dir/new-worktree.txt"
test ! -d "$agent_root/runs/$session"

echo "start issue worker host-publish replay test passed"
