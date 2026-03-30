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

bash "$tools_bin_dir/scaffold-profile.sh" \
  --profile-home "$profile_home" \
  --profile-id alpha-demo \
  --repo-slug acme/alpha-demo >/dev/null

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_PROJECT_ID="alpha-demo" \
  bash "$tools_bin_dir/profile-adopt.sh" --allow-missing-repo
)"

agent_root="/tmp/agent-control-plane-alpha-demo/runtime/alpha-demo"
workspace_file="/tmp/agent-control-plane-alpha-demo/alpha-demo-agents.code-workspace"
profile_yaml_real="$(cd "$profile_home/alpha-demo" && pwd -P)/control-plane.yaml"
workspace_file_real="$(mkdir -p "$(dirname "$workspace_file")" && cd "$(dirname "$workspace_file")" && pwd -P)/$(basename "$workspace_file")"

test -d "$agent_root"
test -d "$agent_root/runs"
test -d "$agent_root/state"
test -d "$agent_root/history"
test -d "/tmp/agent-control-plane-alpha-demo/worktrees"
test -f "$agent_root/control-plane.yaml"
test ! -L "$agent_root/control-plane.yaml"
cmp -s "$agent_root/control-plane.yaml" "$profile_yaml_real"
test -f "$agent_root/workspace.code-workspace"
test ! -L "$agent_root/workspace.code-workspace"
cmp -s "$agent_root/workspace.code-workspace" "$workspace_file_real"
test -f "$workspace_file"
grep -q '"folders": \[\]' "$workspace_file"
grep -q '^PROFILE_ID=alpha-demo$' <<<"$output"
grep -q '^ANCHOR_SYNC_STATUS=skipped-missing-repo$' <<<"$output"
grep -q '^WORKSPACE_SYNC_STATUS=ok$' <<<"$output"
grep -q '^WARNING_COUNT=1$' <<<"$output"
grep -q '^ADOPT_STATUS=ok-with-warnings$' <<<"$output"

echo "profile adopt allow missing repo test passed"
