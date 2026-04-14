#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAPSHOT_BIN="${FLOW_ROOT}/tools/bin/render-dashboard-snapshot.py"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
runs_root="$tmpdir/runtime/demo/runs"
state_root="$tmpdir/runtime/demo/state"
history_root="$tmpdir/runtime/demo/history"

mkdir -p \
  "$profile_dir" \
  "$runs_root" \
  "$history_root" \
  "$state_root/github-outbox/pending" \
  "$state_root/github-outbox/sent" \
  "$state_root/github-outbox/failed"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo-dashboard"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$runs_root"
  state_root: "$state_root"
  history_root: "$history_root"
execution:
  coding_worker: "codex"
  safe_profile: "demo_safe"
  bypass_profile: "demo_bypass"
EOF

cat >"$state_root/github-outbox/pending/comment-pr-123-abc.json" <<'EOF'
{
  "type": "comment",
  "repo_slug": "example/demo-dashboard",
  "number": "123",
  "kind": "pr",
  "body": "Queued PR review outcome while GitHub is unavailable.",
  "body_sha": "abc",
  "created_at": "2026-04-14T09:00:00Z"
}
EOF

cat >"$state_root/github-outbox/pending/approval-124-def.json" <<'EOF'
{
  "type": "approval",
  "repo_slug": "example/demo-dashboard",
  "number": "124",
  "body": "Automated final review passed.",
  "body_sha": "def",
  "created_at": "2026-04-14T09:05:00Z"
}
EOF

cat >"$state_root/github-outbox/sent/labels-125-ghi.json" <<'EOF'
{
  "type": "labels",
  "repo_slug": "example/demo-dashboard",
  "number": "125",
  "created_at": "2026-04-14T09:10:00Z",
  "add": ["agent-reviewed"],
  "remove": []
}
EOF

snapshot="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  python3 "$SNAPSHOT_BIN" --pretty
)"

jq -e '.profile_count == 1' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].counts.pending_github_writes == 2' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].counts.failed_github_writes == 0' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.counts.pending == 2' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.counts.pending_comments == 1' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.counts.pending_approvals == 1' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.counts.pending_label_updates == 0' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.counts.sent == 1' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.pending[0].type == "approval"' >/dev/null <<<"$snapshot"
jq -e '.profiles[0].github_outbox.pending[1].type == "comment"' >/dev/null <<<"$snapshot"

echo "dashboard snapshot includes github outbox test passed"
