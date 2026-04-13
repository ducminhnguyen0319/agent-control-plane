#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/cleanup-worktree.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
profile_root="$tmpdir/profiles/demo"
sync_marker="$tmpdir/sync-called"

mkdir -p "$bin_dir" "$assets_dir" "$profile_root"
cp "$SCRIPT_SRC" "$bin_dir/cleanup-worktree.sh"
cp "$FLOW_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$profile_root/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$tmpdir/repo"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$tmpdir/runtime/demo/runs"
  state_root: "$tmpdir/runtime/demo/state"
  history_root: "$tmpdir/runtime/demo/history"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
EOF

cat >"$bin_dir/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 23
EOF
chmod +x "$bin_dir/agent-project-cleanup-session"

cat >"$bin_dir/sync-vscode-workspace.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >"$sync_marker"
EOF
chmod +x "$bin_dir/sync-vscode-workspace.sh"

set +e
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$tmpdir/profiles" \
  bash "$bin_dir/cleanup-worktree.sh" "/tmp/worktree" "demo-pr-42"
status=$?
set -e

[[ "$status" -eq 23 ]]
[[ -f "$sync_marker" ]]

echo "cleanup worktree syncs workspace after cleanup failure test passed"
