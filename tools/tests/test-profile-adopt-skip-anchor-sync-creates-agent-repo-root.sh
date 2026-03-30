#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_ADOPT_SCRIPT="${FLOW_ROOT}/tools/bin/profile-adopt.sh"
PROFILE_SMOKE_SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"
RENDER_SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"
SYNC_VSCODE_SCRIPT="${FLOW_ROOT}/tools/bin/sync-vscode-workspace.sh"
SYNC_AGENT_REPO_SCRIPT="${FLOW_ROOT}/tools/bin/sync-agent-repo.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
profile_home="$tmpdir/.agent-control-plane/profiles"
tools_bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"

mkdir -p "$tools_bin_dir" "$assets_dir"
cp "$PROFILE_ADOPT_SCRIPT" "$tools_bin_dir/profile-adopt.sh"
cp "$PROFILE_SMOKE_SCRIPT" "$tools_bin_dir/profile-smoke.sh"
cp "$SCAFFOLD_SCRIPT" "$tools_bin_dir/scaffold-profile.sh"
cp "$RENDER_SCRIPT" "$tools_bin_dir/render-flow-config.sh"
cp "$SYNC_VSCODE_SCRIPT" "$tools_bin_dir/sync-vscode-workspace.sh"
cp "$SYNC_AGENT_REPO_SCRIPT" "$tools_bin_dir/sync-agent-repo.sh"
cp "$FLOW_CONFIG_LIB" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$tools_bin_dir/flow-shell-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

agent_root="$tmpdir/runtime/alpha-root"
agent_repo_root="$tmpdir/runtime/alpha-anchor"
worktree_root="$tmpdir/runtime/alpha-worktrees"
workspace_file="$agent_root/alpha-agents.code-workspace"

bash "$tools_bin_dir/scaffold-profile.sh" \
  --profile-home "$profile_home" \
  --profile-id alpha-skip-anchor \
  --repo-slug acme/alpha-skip-anchor \
  --agent-root "$agent_root" \
  --agent-repo-root "$agent_repo_root" \
  --worktree-root "$worktree_root" \
  --vscode-workspace-file "$workspace_file" >/dev/null

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_PROJECT_ID="alpha-skip-anchor" \
  bash "$tools_bin_dir/profile-adopt.sh" --skip-anchor-sync
)"

test -d "$agent_root"
test -d "$worktree_root"
test -d "$agent_repo_root"
test ! -d "$agent_repo_root/.git"
test -f "$workspace_file"
grep -q '^ANCHOR_SYNC_STATUS=skipped$' <<<"$output"
grep -q '^AGENT_REPO_STATUS_AFTER=exists$' <<<"$output"
grep -q "^AGENT_REPO_ROOT=${agent_repo_root}\$" <<<"$output"

echo "profile adopt skip anchor sync creates agent repo root test passed"
