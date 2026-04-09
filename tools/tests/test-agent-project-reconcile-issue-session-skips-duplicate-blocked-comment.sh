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
run_dir="$runs_root/demo-issue-42"
posted_comment_file="$tmpdir/posted-comment.md"

mkdir -p "$bin_dir" "$run_dir" "$history_root" "$repo_root"
git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test"
git -C "$repo_root" config user.email "test@example.com"
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1

cp "$FLOW_ROOT/tools/bin/agent-project-reconcile-issue-session" "$bin_dir/agent-project-reconcile-issue-session"
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

cat >"$bin_dir/sync-recurring-issue-checklist.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
CHECKLIST_SYNC_STATUS=noop
CHECKLIST_TOTAL=5
CHECKLIST_CHECKED=5
CHECKLIST_UNCHECKED=0
CHECKLIST_MATCHED_PR_NUMBERS=
OUT
EOF
chmod +x "$bin_dir/sync-recurring-issue-checklist.sh"

cat >"$tmpdir/bin-gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
posted_comment_file="${TEST_POSTED_COMMENT_FILE:?}"
duplicate_body="${TEST_DUPLICATE_BODY:?}"

if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  printf '5000\n'
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  shift 2

  case "${route}" in
    repos/example/repo/issues/42)
      cat <<JSON
{"number":42,"state":"open","title":"Recurring issue","body":"Checklist:\n- [x] done","labels":[{"name":"agent-keep-open"}]}
JSON
      exit 0
      ;;
    repos/example/repo/issues/42/comments?per_page=100)
      printf '[{"body":%s,"created_at":"2026-03-28T21:57:22Z","updated_at":"2026-03-28T21:57:22Z"}]\n' "$(jq -Rn --arg body "$duplicate_body" '$body')"
      exit 0
      ;;
    repos/example/repo/issues/42/comments)
      printf 'unexpected duplicate post\n' >"${posted_comment_file}"
      exit 0
      ;;
  esac
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$tmpdir/bin-gh"
mkdir -p "$tmpdir/path-bin"
mv "$tmpdir/bin-gh" "$tmpdir/path-bin/gh"

cat >"$run_dir/run.env" <<EOF
ISSUE_ID=42
SESSION=demo-issue-42
WORKTREE=${repo_root}
BRANCH=main
EOF

cat >"$run_dir/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
ISSUE_ID=42
EOF

cat >"$run_dir/runner.env" <<'EOF'
RUNNER_STATE=succeeded
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=
UPDATED_AT=2026-03-28T20:00:00Z
EOF

cat >"$run_dir/issue-comment.md" <<'EOF'
# Blocker: All checklist items already completed

All five checklist items are already implemented and verified.
EOF

out="$(
  PATH="$tmpdir/path-bin:$PATH" \
  AGENT_CONTROL_PLANE_ROOT="$workspace_root" \
  TEST_RUN_DIR="$run_dir" \
  TEST_POSTED_COMMENT_FILE="$posted_comment_file" \
  TEST_DUPLICATE_BODY="$(cat "$run_dir/issue-comment.md")" \
  bash "$bin_dir/agent-project-reconcile-issue-session" \
    --session demo-issue-42 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$out"
grep -q '^OUTCOME=blocked$' <<<"$out"
grep -q '^ACTION=host-comment-blocker$' <<<"$out"
grep -q '^FAILURE_REASON=no-publishable-commits$' <<<"$out"

test ! -e "$posted_comment_file"

echo "issue reconcile skips duplicate blocked comment test passed"
