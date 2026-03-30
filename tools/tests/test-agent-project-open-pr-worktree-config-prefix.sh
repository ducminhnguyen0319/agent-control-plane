#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-open-pr-worktree"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
shim_bin_dir="$tmpdir/shims"
shared_home="$tmpdir/shared-home"
flow_root="$shared_home/skills/openclaw/agent-control-plane"
flow_tools_dir="$flow_root/tools/bin"
flow_assets_dir="$flow_root/assets"
profile_home="$tmpdir/profiles"
capture_file="$tmpdir/capture.log"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"

mkdir -p "$bin_dir" "$shim_bin_dir" "$flow_tools_dir" "$flow_assets_dir" "$profile_home/demo" "$repo_root" "$worktree_root"
printf '# test skill\n' >"$flow_root/SKILL.md"
cp "$SOURCE_SCRIPT" "$bin_dir/agent-project-open-pr-worktree"
cp "$FLOW_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$profile_home/demo/control-plane.yaml" <<'EOF'
id: "demo"
session_naming:
  pr_worktree_branch_prefix: "agent/acp/pr"
EOF

cat >"$flow_tools_dir/agent-init-worktree" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_CAPTURE_FILE:?}"
path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) path="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "${path:?}"
EOF

cat >"$shim_bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$bin_dir/agent-project-open-pr-worktree" \
  "$bin_dir/flow-config-lib.sh" \
  "$bin_dir/flow-shell-lib.sh" \
  "$flow_tools_dir/agent-init-worktree" \
  "$shim_bin_dir/git"

output="$(
  TEST_CAPTURE_FILE="$capture_file" \
  SHARED_AGENT_HOME="$shared_home" \
  ACP_ROOT="$flow_root" \
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_PROJECT_ID="demo" \
  PATH="$shim_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$bin_dir/agent-project-open-pr-worktree" \
    --repo-root "$repo_root" \
    --worktree-root "$worktree_root" \
    --pr-number 77 \
    --head-ref feature/test \
    --stamp 20260325-120000
)"

grep -q -- '--branch agent/acp/pr-77-20260325-120000' "$capture_file"
grep -q -- "--path $worktree_root/pr-77-20260325-120000" "$capture_file"
grep -q -- '^BRANCH=agent/acp/pr-77-20260325-120000$' <<<"$output"

echo "agent-project open pr worktree config prefix test passed"
