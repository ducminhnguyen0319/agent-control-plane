#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-catch-up-scheduled-issue-retries"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_root="$tmpdir/state"
hook_file="$tmpdir/issue-hooks.sh"
events_file="$tmpdir/events.log"
mkdir -p "$state_root/retries/issues"

cat >"$state_root/retries/issues/440.env" <<'EOF'
ATTEMPTS=2
NEXT_ATTEMPT_AT=2026-04-02T09:19:36Z
LAST_REASON=verification-guard-blocked
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
    440)
      printf '{"number":440,"state":"OPEN","body":"Schedule: every 1h","labels":[{"name":"agent-scheduled"},{"name":"smoke-not-ok"},{"name":"agent-schedule-1h"}]}\n'
      ;;
    613)
      printf '{"number":613,"state":"OPEN","body":"Recurring issue","labels":[{"name":"agent-blocked"}]}\n'
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

grep -q '^CATCHUP_SCHEDULED_ISSUE=440$' <<<"$output"
grep -q '^CLEAR:440$' "$events_file"
test ! -f "$state_root/retries/issues/440.env"
test -f "$state_root/retries/issues/613.env"
test -f "$state_root/scheduled-issue-retry-catchup/440.env"
grep -q '^LAST_REASON=verification-guard-blocked$' "$state_root/scheduled-issue-retry-catchup/440.env"

echo "agent-project-catch-up scheduled issue retries clears terminal state test passed"
