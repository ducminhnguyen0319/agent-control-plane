#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"
RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
shared_bin="$shared_home/tools/bin"
shared_assets="$shared_home/assets"
history_root="$tmpdir/history"
runs_root="$tmpdir/runs"
repo_root="$tmpdir/repo"
session="demo-issue-9"
archive_dir="$history_root/${session}-20260326-000000"
capture_file="$tmpdir/capture.log"

mkdir -p "$shared_bin" "$shared_assets" "$history_root" "$runs_root" "$repo_root" "$archive_dir"
printf '{}\n' >"$shared_assets/workflow-catalog.json"
cp "$SOURCE_SCRIPT" "$shared_bin/agent-project-reconcile-issue-session"
cp "$FLOW_ROOT/tools/bin/reconcile-bootstrap-lib.sh" "$shared_bin/reconcile-bootstrap-lib.sh"
cp "$RESIDENT_LIB" "$shared_bin/flow-resident-worker-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"

cat >"$shared_bin/agent-project-worker-status" <<EOF_STATUS
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=%s\n' "$session"
printf 'STATUS=UNKNOWN\n'
EOF_STATUS

cat >"$shared_bin/agent-project-publish-issue-pr" <<'EOF_PUBLISH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGV=%s\n' "$*" >"${TEST_CAPTURE_FILE:?}"
printf 'PUBLISH_STATUS=created-pr\n'
printf 'PR_NUMBER=19\n'
printf 'PR_URL=https://github.com/example/repo/pull/19\n'
EOF_PUBLISH

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF_CLEANUP'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARCHIVE_DIR=%s\n' "${TEST_ARCHIVE_DIR:?}"
EOF_CLEANUP

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/flow-resident-worker-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-publish-issue-pr" \
  "$shared_bin/agent-project-cleanup-session"

cat >"$archive_dir/run.env" <<EOF_RUN
ISSUE_ID=9
BRANCH=agent/demo/issue-9
WORKTREE=$tmpdir/missing-worktree
EOF_RUN

cat >"$archive_dir/runner.env" <<'EOF_RUNNER'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=
EOF_RUNNER

cat >"$archive_dir/result.env" <<'EOF_RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
ISSUE_ID=9
EOF_RESULT

output="$(
  AGENT_CONTROL_PLANE_ROOT="$shared_home" \
  TEST_CAPTURE_FILE="$capture_file" \
  TEST_ARCHIVE_DIR="$archive_dir" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session "$session" \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^ISSUE_ID=9$' <<<"$output"
grep -q '^PR_NUMBER=19$' <<<"$output"
grep -q -- "--history-root $history_root" "$capture_file"

echo "agent-project reconcile issue archived session fallback test passed"
