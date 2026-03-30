#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_ADOPT_SCRIPT="${FLOW_ROOT}/tools/bin/profile-adopt.sh"
PROFILE_SMOKE_SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"
RENDER_SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"
SYNC_VSCODE_SCRIPT="${FLOW_ROOT}/tools/bin/sync-vscode-workspace.sh"
SYNC_AGENT_REPO_SCRIPT="${FLOW_ROOT}/tools/bin/sync-agent-repo.sh"
SYNC_ANCHOR_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-sync-anchor-repo"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
profile_home="$tmpdir/.agent-control-plane/profiles"
tools_bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
remote_repo="$tmpdir/remote.git"
canonical_repo="$tmpdir/canonical"
retained_repo="$tmpdir/retained"
anchor_repo="$tmpdir/anchor"
runtime_root="$tmpdir/runtime/alpha"
workspace_file="$tmpdir/alpha.code-workspace"
worktree_root="$tmpdir/worktrees"

mkdir -p "$tools_bin_dir" "$assets_dir"
cp "$PROFILE_ADOPT_SCRIPT" "$tools_bin_dir/profile-adopt.sh"
cp "$PROFILE_SMOKE_SCRIPT" "$tools_bin_dir/profile-smoke.sh"
cp "$SCAFFOLD_SCRIPT" "$tools_bin_dir/scaffold-profile.sh"
cp "$RENDER_SCRIPT" "$tools_bin_dir/render-flow-config.sh"
cp "$SYNC_VSCODE_SCRIPT" "$tools_bin_dir/sync-vscode-workspace.sh"
cp "$SYNC_AGENT_REPO_SCRIPT" "$tools_bin_dir/sync-agent-repo.sh"
cp "$SYNC_ANCHOR_SCRIPT" "$tools_bin_dir/agent-project-sync-anchor-repo"
cp "$FLOW_CONFIG_LIB" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$tools_bin_dir/flow-shell-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

git init --bare "$remote_repo" >/dev/null 2>&1
git clone "$remote_repo" "$canonical_repo" >/dev/null 2>&1
git -C "$canonical_repo" config user.name "Test"
git -C "$canonical_repo" config user.email "test@example.com"
git -C "$canonical_repo" checkout -b main >/dev/null 2>&1
printf 'seed\n' >"$canonical_repo/README.md"
git -C "$canonical_repo" add README.md
git -C "$canonical_repo" commit -m "init" >/dev/null 2>&1
git -C "$canonical_repo" push -u origin main >/dev/null 2>&1
git clone "$remote_repo" "$retained_repo" >/dev/null 2>&1
git -C "$retained_repo" checkout main >/dev/null 2>&1

bash "$tools_bin_dir/scaffold-profile.sh" \
  --profile-home "$profile_home" \
  --profile-id alpha \
  --repo-slug acme/alpha \
  --repo-root "$canonical_repo" \
  --agent-repo-root "$anchor_repo" \
  --retained-repo-root "$retained_repo" \
  --agent-root "$runtime_root" \
  --worktree-root "$worktree_root" \
  --vscode-workspace-file "$workspace_file" >/dev/null

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_PROJECT_ID="alpha" \
  bash "$tools_bin_dir/profile-adopt.sh"
)"

workspace_file_real="$(cd "$(dirname "$workspace_file")" && pwd -P)/$(basename "$workspace_file")"
profile_yaml_real="$(cd "$profile_home/alpha" && pwd -P)/control-plane.yaml"

test -d "$anchor_repo/.git"
test -f "$runtime_root/control-plane.yaml"
test ! -L "$runtime_root/control-plane.yaml"
cmp -s "$runtime_root/control-plane.yaml" "$profile_yaml_real"
test -f "$runtime_root/workspace.code-workspace"
test ! -L "$runtime_root/workspace.code-workspace"
cmp -s "$runtime_root/workspace.code-workspace" "$workspace_file_real"
test -f "$workspace_file"
grep -q "$anchor_repo" "$workspace_file"
grep -q "$retained_repo" "$workspace_file"
test "$(git -C "$anchor_repo" remote get-url origin)" = "$remote_repo"
grep -q '^ANCHOR_SYNC_STATUS=ok$' <<<"$output"
grep -q '^WORKSPACE_SYNC_STATUS=ok$' <<<"$output"
grep -q '^WARNING_COUNT=0$' <<<"$output"
grep -q '^ADOPT_STATUS=ok$' <<<"$output"

echo "profile adopt syncs anchor and workspace test passed"
