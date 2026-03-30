#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNINSTALL_BIN="${FLOW_ROOT}/tools/bin/uninstall-project-launchd.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
workspace_dir="$home_dir/.agent-runtime/control-plane/workspace"
launch_agents_dir="$home_dir/Library/LaunchAgents"
label="ai.agent.project.demo"
wrapper_path="$workspace_dir/bin/agent-project-demo-launchd.sh"
plist_path="$launch_agents_dir/$label.plist"

mkdir -p "$(dirname "$wrapper_path")" "$launch_agents_dir"
printf '#!/usr/bin/env bash\n' >"$wrapper_path"
printf '<plist></plist>\n' >"$plist_path"

output="$(
  ACP_PROJECT_RUNTIME_HOME_DIR="$home_dir" \
  ACP_PROJECT_RUNTIME_WORKSPACE_DIR="$workspace_dir" \
  ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR="$launch_agents_dir" \
  ACP_PROJECT_RUNTIME_SKIP_LAUNCHCTL=1 \
  bash "$UNINSTALL_BIN" --profile-id demo
)"

grep -q '^LAUNCHD_UNINSTALL_STATUS=ok$' <<<"$output"
grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q "^LABEL=$label$" <<<"$output"
grep -q "^PLIST=$plist_path$" <<<"$output"
grep -q "^WRAPPER=$wrapper_path$" <<<"$output"
[[ ! -e "$wrapper_path" ]]
[[ ! -e "$plist_path" ]]

echo "uninstall project launchd test passed"
