#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_BIN="${FLOW_ROOT}/tools/bin/install-dashboard-launchd.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
workspace_dir="$home_dir/.agent-runtime/control-plane/workspace"
launch_agents_dir="$home_dir/Library/LaunchAgents"
log_dir="$home_dir/.agent-runtime/logs"
source_home="$tmpdir/source-home"
runtime_home="$home_dir/.agent-runtime/runtime-home"
profile_registry_root="$home_dir/.agent-runtime/control-plane/profiles"
sync_script="$tmpdir/sync.sh"
bootstrap_script="$tmpdir/bootstrap.sh"
label="ai.agent.dashboard.test"

mkdir -p "$workspace_dir" "$launch_agents_dir" "$log_dir" "$source_home" "$runtime_home" "$profile_registry_root"

cat >"$sync_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$sync_script"

cat >"$bootstrap_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bootstrap_script"

output="$(
  ACP_DASHBOARD_HOME_DIR="$home_dir" \
  ACP_DASHBOARD_SOURCE_HOME="$source_home" \
  ACP_DASHBOARD_RUNTIME_HOME="$runtime_home" \
  ACP_DASHBOARD_WORKSPACE_DIR="$workspace_dir" \
  ACP_DASHBOARD_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  ACP_DASHBOARD_LAUNCH_AGENTS_DIR="$launch_agents_dir" \
  ACP_DASHBOARD_LOG_DIR="$log_dir" \
  ACP_DASHBOARD_SYNC_SCRIPT="$sync_script" \
  ACP_DASHBOARD_BOOTSTRAP_SCRIPT="$bootstrap_script" \
  ACP_DASHBOARD_SKIP_LAUNCHCTL=1 \
  bash "$INSTALL_BIN" --host 127.0.0.1 --port 9911 --label "$label"
)"

wrapper_path="$workspace_dir/bin/agent-dashboard-launchd.sh"
plist_path="$launch_agents_dir/$label.plist"

grep -q '^LAUNCHD_INSTALL_STATUS=skipped-launchctl$' <<<"$output"
grep -q "^LABEL=$label$" <<<"$output"
grep -q "^PLIST=$plist_path$" <<<"$output"
grep -q "^WRAPPER=$wrapper_path$" <<<"$output"
grep -q '^URL=http://127.0.0.1:9911$' <<<"$output"

test -x "$wrapper_path"
test -f "$plist_path"
grep -q "^export ACP_DASHBOARD_HOME_DIR='$home_dir'$" "$wrapper_path"
grep -q "^export ACP_DASHBOARD_SOURCE_HOME='$source_home'$" "$wrapper_path"
grep -q "^export ACP_DASHBOARD_RUNTIME_HOME='$runtime_home'$" "$wrapper_path"
grep -q "^export ACP_DASHBOARD_PROFILE_REGISTRY_ROOT='$profile_registry_root'$" "$wrapper_path"
grep -q "^export ACP_DASHBOARD_HOST='127.0.0.1'$" "$wrapper_path"
grep -q "^export ACP_DASHBOARD_PORT='9911'$" "$wrapper_path"
grep -q "^export ACP_DASHBOARD_SYNC_SCRIPT='$sync_script'$" "$wrapper_path"
grep -q "exec bash '$bootstrap_script'$" "$wrapper_path"

grep -q "<string>$label</string>" "$plist_path"
grep -q "<string>$wrapper_path</string>" "$plist_path"
grep -q "<string>$log_dir/agent-dashboard.stderr.log</string>" "$plist_path"
grep -q "<string>$log_dir/agent-dashboard.stdout.log</string>" "$plist_path"
grep -q '<key>KeepAlive</key>' "$plist_path"
grep -q '<true/>' "$plist_path"

echo "install dashboard launchd test passed"
