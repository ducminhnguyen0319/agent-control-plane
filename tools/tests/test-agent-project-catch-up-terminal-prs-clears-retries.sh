#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-catch-up-merged-prs"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_root="$tmpdir/state"
hook_file="$tmpdir/pr-hooks.sh"
events_file="$tmpdir/events.log"
mkdir -p "$state_root/retries/prs"

cat >"$hook_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

flow_github_pr_list_json() {
  local state="${2:-open}"
  case "$state" in
    merged)
      printf '[{"number":101,"mergedAt":"2026-04-03T18:00:00Z","createdAt":"2026-04-03T17:00:00Z"}]\n'
      ;;
    closed)
      printf '[{"number":101,"mergedAt":"2026-04-03T18:00:00Z","createdAt":"2026-04-03T17:00:00Z"},{"number":102,"mergedAt":"","createdAt":"2026-04-03T16:00:00Z"}]\n'
      ;;
    *)
      printf '[]\n'
      ;;
  esac
}

heartbeat_pr_risk_json() {
  local pr_number="${1:?pr number required}"
  case "$pr_number" in
    101) printf '{"isManagedByAgent":true,"linkedIssueId":"501"}\n' ;;
    102) printf '{"isManagedByAgent":true,"linkedIssueId":"502"}\n' ;;
    *) printf '{}\n' ;;
  esac
}

flow_github_issue_view_json() {
  local issue_id="${2:-}"
  case "$issue_id" in
    501) printf '{"state":"OPEN","labels":[]}\n' ;;
    502) printf '{"state":"OPEN","labels":[]}\n' ;;
    *) printf '{}\n' ;;
  esac
}

flow_github_issue_close() {
  local issue_id="${2:-}"
  printf 'ISSUE_CLOSE:%s\n' "$issue_id" >>"${TEST_EVENTS_FILE:?}"
}

pr_clear_retry() {
  printf 'CLEAR:%s\n' "${PR_NUMBER:?}" >>"${TEST_EVENTS_FILE:?}"
}

pr_after_merged() {
  printf 'MERGED:%s\n' "${1:?}" >>"${TEST_EVENTS_FILE:?}"
}

pr_after_closed() {
  printf 'CLOSED:%s\n' "${1:?}" >>"${TEST_EVENTS_FILE:?}"
}

pr_cleanup_merged_residue() {
  printf 'RESIDUE:%s\n' "${1:?}" >>"${TEST_EVENTS_FILE:?}"
}

pr_cleanup_linked_issue_session() {
  printf 'ISSUE_SESSION_CLEANUP:%s\n' "${1:?}" >>"${TEST_EVENTS_FILE:?}"
}

pr_linked_issue_should_close() {
  printf 'yes\n'
}
EOF

chmod +x "$hook_file"
export TEST_EVENTS_FILE="$events_file"

output="$(
  bash "$SOURCE_SCRIPT" \
    --repo-slug "example/repo" \
    --state-root "$state_root" \
    --hook-file "$hook_file" \
    --limit 20
)"

grep -q '^CATCHUP_MERGED_PR=101$' <<<"$output"
grep -q '^CATCHUP_CLOSED_PR=102$' <<<"$output"

grep -q '^CLEAR:101$' "$events_file"
grep -q '^MERGED:101$' "$events_file"
grep -q '^RESIDUE:101$' "$events_file"
grep -q '^ISSUE_SESSION_CLEANUP:501$' "$events_file"
grep -q '^ISSUE_CLOSE:501$' "$events_file"

grep -q '^CLEAR:102$' "$events_file"
grep -q '^CLOSED:102$' "$events_file"
grep -q '^RESIDUE:102$' "$events_file"
if grep -q '^ISSUE_CLOSE:502$' "$events_file"; then
  echo "closed non-merged PR should not auto-close linked issue" >&2
  exit 1
fi

test -f "$state_root/merged-pr-catchup-github/101.env"
test -f "$state_root/closed-pr-catchup-github/102.env"
grep -q '^PR_STATE=merged$' "$state_root/merged-pr-catchup-github/101.env"
grep -q '^PR_STATE=closed$' "$state_root/closed-pr-catchup-github/102.env"

echo "agent-project-catch-up terminal PRs clears retries test passed"
