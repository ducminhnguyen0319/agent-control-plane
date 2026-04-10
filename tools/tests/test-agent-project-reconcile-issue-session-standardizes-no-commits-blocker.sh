#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_root="$tmpdir/workspace"
bin_dir="$workspace_root/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
run_dir="$runs_root/demo-issue-501"
posted_comment_file="$tmpdir/posted-comment.md"

mkdir -p "$bin_dir" "$run_dir" "$history_root" "$repo_root"
git -C "$repo_root" init -b main >/dev/null 2>&1

cp "$FLOW_ROOT/tools/bin/agent-project-reconcile-issue-session" "$bin_dir/agent-project-reconcile-issue-session"
cp "$FLOW_ROOT/tools/bin/reconcile-bootstrap-lib.sh" "$bin_dir/"
cp "$FLOW_ROOT/tools/bin/flow-config-lib.sh" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_ROOT/tools/bin/flow-shell-lib.sh" "$bin_dir/flow-shell-lib.sh"
cp "$FLOW_ROOT/tools/bin/flow-resident-worker-lib.sh" "$bin_dir/flow-resident-worker-lib.sh"

cat >"$bin_dir/agent-project-worker-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${TEST_RUN_DIR:?}/run.env
OUT
EOF
chmod +x "$bin_dir/agent-project-worker-status"

cat >"$bin_dir/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/agent-project-cleanup-session"

cat >"$bin_dir/agent-project-publish-issue-pr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "branch agent/demo/issue-501-keep-open has no commits ahead of origin/main; nothing to publish" >&2
exit 1
EOF
chmod +x "$bin_dir/agent-project-publish-issue-pr"

cat >"$bin_dir/sync-recurring-issue-checklist.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
CHECKLIST_SYNC_STATUS=updated
CHECKLIST_TOTAL=3
CHECKLIST_CHECKED=3
CHECKLIST_UNCHECKED=0
CHECKLIST_MATCHED_PR_NUMBERS=7,8,9
OUT
EOF
chmod +x "$bin_dir/sync-recurring-issue-checklist.sh"

cat >"$tmpdir/bin-gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
posted_comment_file="${TEST_POSTED_COMMENT_FILE:?}"

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  shift 2
  if [[ "${route}" == "repos/example/repo/issues/501/comments" ]]; then
    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f)
          if [[ "${2:-}" == body=* ]]; then
            body="${2#body=}"
            shift 2
            continue
          fi
          ;;
      esac
      shift
    done
    printf '%s\n' "${body}" >"${posted_comment_file}"
    exit 0
  fi
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$tmpdir/bin-gh"

mkdir -p "$tmpdir/path-bin"
mv "$tmpdir/bin-gh" "$tmpdir/path-bin/gh"

cat >"$run_dir/run.env" <<'EOF'
ISSUE_ID=501
SESSION=demo-issue-501
WORKTREE=/tmp/mock-worktree
BRANCH=agent/demo/issue-501-keep-open
EOF

cat >"$run_dir/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
ISSUE_ID=501
EOF

cat >"$run_dir/runner.env" <<'EOF'
RUNNER_STATE=succeeded
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=
UPDATED_AT=2026-03-28T20:00:00Z
EOF

out="$(
  PATH="$tmpdir/path-bin:$PATH" \
  AGENT_CONTROL_PLANE_ROOT="$workspace_root" \
  TEST_RUN_DIR="$run_dir" \
  TEST_POSTED_COMMENT_FILE="$posted_comment_file" \
  bash "$bin_dir/agent-project-reconcile-issue-session" \
    --session demo-issue-501 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$out"
grep -q '^OUTCOME=blocked$' <<<"$out"
grep -q '^ACTION=host-comment-blocker$' <<<"$out"
grep -q '^FAILURE_REASON=no-publishable-commits$' <<<"$out"

grep -q '^# Blocker: All checklist items already completed$' "$run_dir/issue-comment.md"
grep -q 'refresh the issue body with new unchecked improvement items' "$run_dir/issue-comment.md"
grep -q 'Recently matched PRs: #7, #8, #9' "$run_dir/issue-comment.md"

test -f "$posted_comment_file"
grep -q '^# Blocker: All checklist items already completed$' "$posted_comment_file"

echo "issue reconcile no-commits blocker standardization test passed"
