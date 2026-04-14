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
      printf '[]\n'
      ;;
    closed)
      printf '[{"number":202,"mergedAt":"","createdAt":"2026-04-03T16:00:00Z"}]\n'
      ;;
    *)
      printf '[]\n'
      ;;
  esac
}

heartbeat_pr_risk_json() {
  local pr_number="${1:?pr number required}"
  case "$pr_number" in
    202) printf '{"isManagedByAgent":true,"linkedIssueId":"602"}\n' ;;
    *) printf '{}\n' ;;
  esac
}

flow_github_issue_view_json() {
  printf '{"state":"OPEN","labels":[]}\n'
}

pr_clear_retry() {
  printf 'CLEAR:%s\n' "${PR_NUMBER:?}" >>"${TEST_EVENTS_FILE:?}"
}

pr_cleanup_merged_residue() {
  printf 'RESIDUE:%s\n' "${1:?}" >>"${TEST_EVENTS_FILE:?}"
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

grep -q '^CATCHUP_CLOSED_PR=202$' <<<"$output"
grep -q '^CLEAR:202$' "$events_file"
grep -q '^RESIDUE:202$' "$events_file"
test -f "$state_root/closed-pr-catchup/202.env"
grep -q '^PR_STATE=closed$' "$state_root/closed-pr-catchup/202.env"

echo "agent-project-catch-up terminal PRs defaults closed hook test passed"
