#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/audit-agent-worktrees.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
flow_root="$shared_home/skills/openclaw/agent-control-plane"
bin_dir="$tmpdir/bin"
profile_root="$tmpdir/profiles"
profile_dir="$profile_root/demo"
agent_root="$tmpdir/runtime/demo"
repo_root="$tmpdir/repo"
worktree_root="$agent_root/worktrees"
state_root="$agent_root/state"
runs_root="$agent_root/runs"
artifact_dir="$worktree_root/issue-439-20260403-152810"
stale_lane_dir="$state_root/resident-workers/issues/issue-lane-scheduled-3600-codex-safe"

mkdir -p \
  "$flow_root/tools/bin" \
  "$flow_root/hooks" \
  "$profile_dir" \
  "$bin_dir" \
  "$agent_root/history" \
  "$repo_root" \
  "$worktree_root" \
  "$stale_lane_dir" \
  "$runs_root"

cp "$SCRIPT_SRC" "$flow_root/tools/bin/audit-agent-worktrees.sh"
cp "$FLOW_CONFIG_LIB" "$flow_root/tools/bin/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$flow_root/tools/bin/flow-shell-lib.sh"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$repo_root"
runtime:
  orchestrator_agent_root: "$agent_root"
  agent_repo_root: "$repo_root"
  worktree_root: "$worktree_root"
  runs_root: "$runs_root"
  state_root: "$state_root"
  history_root: "$agent_root/history"
execution:
  coding_worker: "codex"
EOF

mkdir -p "$artifact_dir/.openclaw-artifacts"
cat >"$stale_lane_dir/metadata.env" <<EOF
WORKTREE=$stale_lane_dir/worktree
WORKTREE_REALPATH=$worktree_root/issue-438-20260403-195620
ISSUE_ID=438
LAST_STATUS=SUCCEEDED
EOF

git -C "$repo_root" init >/dev/null 2>&1
git -C "$repo_root" checkout -b main >/dev/null 2>&1

cat >"$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
chmod +x "$bin_dir/tmux"

output="$(
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  SHARED_AGENT_HOME="$shared_home" \
  ACP_PROFILE_REGISTRY_ROOT="$profile_root" \
  ACP_PROJECT_ID="demo" \
  AGENT_PROJECT_ID="demo" \
  ACP_AGENT_ROOT="$agent_root" \
  ACP_WORKTREE_ROOT="$worktree_root" \
  ACP_RUNS_ROOT="$runs_root" \
  ACP_STATE_ROOT="$state_root" \
  ACP_AGENT_REPO_ROOT="$repo_root" \
    bash "$flow_root/tools/bin/audit-agent-worktrees.sh" --cleanup
)"

grep -q '^CLEARED_STALE_RESIDENT_WORKTREE=' <<<"$output"
grep -q '^ARTIFACT_ONLY_WORKTREE_COUNT=1$' <<<"$output"
grep -q '^ARTIFACT_ONLY_WORKTREE_CLEANED=1$' <<<"$output"
grep -q "^WORKTREE_REALPATH=''$" "$stale_lane_dir/metadata.env"
test ! -d "$artifact_dir"

echo "audit-agent-worktrees clears stale metadata and artifact residue test passed"
