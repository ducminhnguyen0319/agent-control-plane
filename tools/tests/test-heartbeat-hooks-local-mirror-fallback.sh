#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

node_bin_dir="$(dirname "$(command -v node)")"
state_root="$tmpdir/state"

mkdir -p "$state_root"

export PATH="$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export F_LOSNING_REPO_SLUG="example/repo"

# shellcheck source=/dev/null
source "$HOOKS_FILE"

REPO_SLUG="example/repo"
STATE_ROOT="$state_root"
AGENT_PR_PREFIXES_JSON='["codex/"]'
AGENT_PR_ISSUE_CAPTURE_REGEX='issue-(?<id>[0-9]+)'
AGENT_PR_HANDOFF_LABEL="agent-handoff"
AGENT_EXCLUSIVE_LABEL="agent-exclusive"
TEST_LIVE_FETCH_MODE="success"

flow_github_issue_list_json_live() {
  [[ "${TEST_LIVE_FETCH_MODE:-success}" == "success" ]] || return 1
  cat <<'JSON'
[
  {
    "number": 615,
    "createdAt": "2026-04-14T10:00:00Z",
    "updatedAt": "2026-04-14T10:00:00Z",
    "title": "Recurring agent issue",
    "url": "https://example.test/issues/615",
    "labels": [{"name": "agent-exclusive"}]
  }
]
JSON
}

flow_github_pr_list_json_live() {
  [[ "${TEST_LIVE_FETCH_MODE:-success}" == "success" ]] || return 1
  cat <<'JSON'
[
  {
    "number": 712,
    "title": "Agent handoff PR",
    "body": "Fixes #615",
    "url": "https://example.test/pulls/712",
    "headRefName": "codex/issue-615",
    "createdAt": "2026-04-14T10:01:00Z",
    "mergedAt": "",
    "isDraft": false,
    "labels": [{"name": "agent-handoff"}],
    "comments": [{"body": "handoff ready"}]
  }
]
JSON
}

flow_github_issue_view_json_live() {
  [[ "${TEST_LIVE_FETCH_MODE:-success}" == "success" ]] || return 1
  cat <<'JSON'
{
  "number": 615,
  "state": "OPEN",
  "title": "Recurring agent issue",
  "body": "Schedule: every 1h",
  "url": "https://example.test/issues/615",
  "labels": [{"name": "agent-keep-open"}, {"name": "agent-exclusive"}],
  "comments": [],
  "createdAt": "2026-04-14T10:00:00Z",
  "updatedAt": "2026-04-14T10:00:00Z"
}
JSON
}

issue_list_live="$(heartbeat_cached_issue_list_json)"
pr_list_live="$(heartbeat_cached_pr_list_json)"
open_issue_ids_live="$(heartbeat_open_agent_pr_issue_ids)"
ready_issue_ids_live="$(heartbeat_list_ready_issue_ids)"

[[ "$(heartbeat_issue_is_recurring 615)" == "yes" ]]
[[ "$(heartbeat_issue_is_scheduled 615)" == "yes" ]]
[[ "$(heartbeat_issue_is_exclusive 615)" == "yes" ]]
grep -q '615' <<<"${open_issue_ids_live}"
if [[ -n "${ready_issue_ids_live}" ]]; then
  echo "issue with open agent PR should not appear as ready" >&2
  exit 1
fi

mirror_dir="$state_root/github-mirror/heartbeat"
test -f "$mirror_dir/issues-open-100.json"
test -f "$mirror_dir/issues-open-100.env"
test -f "$mirror_dir/prs-open-100.json"
test -f "$mirror_dir/issue-615.json"
grep -q '^SOURCE=live$' "$mirror_dir/issues-open-100.env"

heartbeat_invalidate_snapshot_cache
TEST_LIVE_FETCH_MODE="failure"

issue_list_mirror="$(heartbeat_cached_issue_list_json)"
pr_list_mirror="$(heartbeat_cached_pr_list_json)"
open_issue_ids_mirror="$(heartbeat_open_agent_pr_issue_ids)"
ready_issue_ids_mirror="$(heartbeat_list_ready_issue_ids)"

[[ "${issue_list_mirror}" == "${issue_list_live}" ]]
[[ "${pr_list_mirror}" == "${pr_list_live}" ]]
[[ "$(heartbeat_issue_is_recurring 615)" == "yes" ]]
[[ "$(heartbeat_issue_is_scheduled 615)" == "yes" ]]
[[ "$(heartbeat_issue_is_exclusive 615)" == "yes" ]]
grep -q '615' <<<"${open_issue_ids_mirror}"
if [[ -n "${ready_issue_ids_mirror}" ]]; then
  echo "mirrored open agent PR should continue excluding the issue from ready queue" >&2
  exit 1
fi

echo "heartbeat hooks local mirror fallback test passed"
