#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_BIN="${FLOW_ROOT}/tools/bin/install-project-launchd.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
workspace_dir="$home_dir/.agent-runtime/control-plane/workspace"
launch_agents_dir="$home_dir/Library/LaunchAgents"
log_dir="$home_dir/.agent-runtime/logs"
source_home="$tmpdir/source-home"
runtime_home="$home_dir/.agent-runtime/runtime-home"
profile_registry_root="$home_dir/.agent-runtime/control-plane/profiles"
profile_dir="$profile_registry_root/demo"
sync_script="$tmpdir/sync.sh"
bootstrap_script="$tmpdir/bootstrap.sh"
supervisor_script="$tmpdir/supervisor.sh"
label="ai.agent.project.demo-test"

mkdir -p "$workspace_dir" "$launch_agents_dir" "$log_dir" "$source_home" "$runtime_home" "$profile_dir"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$tmpdir/runtime/demo/runs"
  state_root: "$tmpdir/runtime/demo/state"
  history_root: "$tmpdir/runtime/demo/history"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

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

cat >"$supervisor_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$supervisor_script"

output="$(
  ACP_PROJECT_RUNTIME_HOME_DIR="$home_dir" \
  ACP_PROJECT_RUNTIME_SOURCE_HOME="$source_home" \
  ACP_PROJECT_RUNTIME_RUNTIME_HOME="$runtime_home" \
  ACP_PROJECT_RUNTIME_WORKSPACE_DIR="$workspace_dir" \
  ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR="$launch_agents_dir" \
  ACP_PROJECT_RUNTIME_LOG_DIR="$log_dir" \
  ACP_PROJECT_RUNTIME_SYNC_SCRIPT="$sync_script" \
  ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT="$bootstrap_script" \
  ACP_PROJECT_RUNTIME_SUPERVISOR_SCRIPT="$supervisor_script" \
  ACP_PROJECT_RUNTIME_SKIP_LAUNCHCTL=1 \
  bash "$INSTALL_BIN" --profile-id demo --label "$label" --delay-seconds 3 --interval-seconds 20
)"

wrapper_path="$workspace_dir/bin/agent-project-demo-launchd.sh"
plist_path="$launch_agents_dir/$label.plist"

grep -q '^LAUNCHD_INSTALL_STATUS=skipped-launchctl$' <<<"$output"
grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q "^LABEL=$label$" <<<"$output"
grep -q "^PLIST=$plist_path$" <<<"$output"
grep -q "^WRAPPER=$wrapper_path$" <<<"$output"

test -x "$wrapper_path"
test -f "$plist_path"
grep -q "^export ACP_PROJECT_RUNTIME_HOME_DIR='$home_dir'$" "$wrapper_path"
grep -q "^export ACP_PROJECT_RUNTIME_SOURCE_HOME='$source_home'$" "$wrapper_path"
grep -q "^export ACP_PROJECT_RUNTIME_RUNTIME_HOME='$runtime_home'$" "$wrapper_path"
grep -q "^export ACP_PROJECT_RUNTIME_PROFILE_ID='demo'$" "$wrapper_path"
grep -q "^export ACP_PROJECT_RUNTIME_ENV_FILE='$profile_dir/runtime.env'$" "$wrapper_path"
grep -q "^export ACP_PROFILE_REGISTRY_ROOT='$profile_registry_root'$" "$wrapper_path"
grep -q "exec bash '$supervisor_script' --bootstrap-script '$bootstrap_script' --pid-file '$tmpdir/runtime/demo/state/runtime-supervisor.pid' --delay-seconds '3' --interval-seconds '20'$" "$wrapper_path"

grep -q "<string>$label</string>" "$plist_path"
grep -q "<string>$wrapper_path</string>" "$plist_path"
grep -q "<string>$log_dir/agent-project-demo.stderr.log</string>" "$plist_path"
grep -q "<string>$log_dir/agent-project-demo.stdout.log</string>" "$plist_path"
grep -q '<key>KeepAlive</key>' "$plist_path"

echo "install project launchd test passed"
