#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/reconcile-pr-worker.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_bin_dir="$tmpdir/workspace/bin"
shared_home="$tmpdir/shared-home"
flow_root="$shared_home/skills/openclaw/agent-control-plane"
flow_tools_dir="$flow_root/tools/bin"
flow_assets_dir="$flow_root/assets"
hooks_dir="$flow_root/hooks"
profile_home="$tmpdir/profiles"
capture_file="$tmpdir/capture.log"

mkdir -p "$workspace_bin_dir" "$flow_tools_dir" "$flow_assets_dir" "$hooks_dir" "$profile_home/demo"
cp "$SOURCE_SCRIPT" "$workspace_bin_dir/reconcile-pr-worker.sh"
cp "$FLOW_CONFIG_LIB" "$workspace_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$workspace_bin_dir/flow-shell-lib.sh"

cat >"$profile_home/demo/control-plane.yaml" <<EOF
id: "demo"
repo:
  slug: "example/repo"
runtime:
  orchestrator_agent_root: "$tmpdir/agent-root"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$tmpdir/runs"
EOF

cat >"$flow_tools_dir/agent-project-reconcile-pr-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGV=%s\n' "$*" >"${TEST_CAPTURE_FILE:?}"
printf 'ACP_RUNS_ROOT=%s\n' "${ACP_RUNS_ROOT:-}" >>"${TEST_CAPTURE_FILE:?}"
printf 'F_LOSNING_RUNS_ROOT=%s\n' "${F_LOSNING_RUNS_ROOT:-}" >>"${TEST_CAPTURE_FILE:?}"
EOF

cat >"$hooks_dir/pr-reconcile-hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$workspace_bin_dir/reconcile-pr-worker.sh" \
  "$workspace_bin_dir/flow-config-lib.sh" \
  "$workspace_bin_dir/flow-shell-lib.sh" \
  "$flow_tools_dir/agent-project-reconcile-pr-session" \
  "$hooks_dir/pr-reconcile-hooks.sh"

expected_hook_file="$(cd "$hooks_dir" && pwd -P)/pr-reconcile-hooks.sh"

TEST_CAPTURE_FILE="$capture_file" \
SHARED_AGENT_HOME="$shared_home" \
ACP_ROOT="$flow_root" \
ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
ACP_PROJECT_ID="demo" \
bash "$workspace_bin_dir/reconcile-pr-worker.sh" "acp-pr-55"

grep -q -- '--session acp-pr-55' "$capture_file"
grep -q -- '--repo-slug example/repo' "$capture_file"
grep -q -- "--repo-root $tmpdir/repo" "$capture_file"
grep -q -- "--runs-root $tmpdir/runs" "$capture_file"
grep -q -- "--history-root $tmpdir/agent-root/history" "$capture_file"
grep -q -- "--hook-file $expected_hook_file" "$capture_file"
grep -q -- "^ACP_RUNS_ROOT=$tmpdir/runs$" "$capture_file"
grep -q -- "^F_LOSNING_RUNS_ROOT=$tmpdir/runs$" "$capture_file"

echo "reconcile-pr-worker acp config routing test passed"
