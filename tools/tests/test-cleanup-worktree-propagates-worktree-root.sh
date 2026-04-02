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
capture_file="$tmpdir/capture.env"

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

cat >"$bin_dir/agent-project-cleanup-session" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'AGENT_PROJECT_WORKTREE_ROOT=%s\n' "\${AGENT_PROJECT_WORKTREE_ROOT:-}" >"$capture_file"
printf 'F_LOSNING_WORKTREE_ROOT=%s\n' "\${F_LOSNING_WORKTREE_ROOT:-}" >>"$capture_file"
printf '%s\n' "\$*" >>"$capture_file"
EOF
chmod +x "$bin_dir/agent-project-cleanup-session"

cat >"$bin_dir/sync-vscode-workspace.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/sync-vscode-workspace.sh"

ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$tmpdir/profiles" \
  bash "$bin_dir/cleanup-worktree.sh" "/tmp/worktree" "demo-pr-42"

grep -q "^AGENT_PROJECT_WORKTREE_ROOT=$tmpdir/worktrees$" "$capture_file"
grep -q "^F_LOSNING_WORKTREE_ROOT=$tmpdir/worktrees$" "$capture_file"
grep -q -- '--worktree /tmp/worktree' "$capture_file"
grep -q -- '--session demo-pr-42' "$capture_file"

echo "cleanup worktree propagates worktree root test passed"
