#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-catch-up-issue-pr-links"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_root="$tmpdir/state"
hook_file="$tmpdir/issue-hooks.sh"
events_file="$tmpdir/events.log"
mkdir -p "$state_root/retries/issues"

cat >"$state_root/retries/issues/256.env" <<'EOF'
ATTEMPTS=2
NEXT_ATTEMPT_AT=2026-04-03T18:57:21Z
LAST_REASON=host-publish-failed
EOF

cat >"$state_root/retries/issues/613.env" <<'EOF'
ATTEMPTS=10
NEXT_ATTEMPT_AT=2026-04-03T19:01:59Z
LAST_REASON=worker-preflight-network-blocked
EOF

cat >"$hook_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

flow_github_issue_view_json() {
  local issue_id="${2:-}"
  case "$issue_id" in
    256)
      printf '{"number":256,"comments":[{"body":"Opened PR #749: https://example.test/pull/749","createdAt":"2026-04-03T18:56:35Z"}]}\n'
      ;;
    *)
      printf '{}\n'
      ;;
  esac
}

flow_github_pr_view_json() {
  local pr_number="${2:-}"
  case "$pr_number" in
    749)
      printf '{"number":749,"state":"OPEN"}\n'
      ;;
    *)
      printf '{}\n'
      ;;
  esac
}

issue_clear_retry() {
  printf 'CLEAR:%s\n' "${ISSUE_ID:?}" >>"${TEST_EVENTS_FILE:?}"
  rm -f "${TEST_STATE_ROOT:?}/retries/issues/${ISSUE_ID}.env"
}
EOF

chmod +x "$hook_file"
export TEST_EVENTS_FILE="$events_file"
export TEST_STATE_ROOT="$state_root"

output="$(
  bash "$SOURCE_SCRIPT" \
    --repo-slug "example/repo" \
    --state-root "$state_root" \
    --hook-file "$hook_file" \
    --limit 20
)"

grep -q '^CATCHUP_LINKED_PR_ISSUE=256$' <<<"$output"
grep -q '^CLEAR:256$' "$events_file"
test ! -f "$state_root/retries/issues/256.env"
test -f "$state_root/retries/issues/613.env"
test -f "$state_root/linked-pr-issue-catchup/256.env"
grep -q '^LINKED_PR=749$' "$state_root/linked-pr-issue-catchup/256.env"

echo "agent-project-catch-up issue PR links clears host-publish retry test passed"
