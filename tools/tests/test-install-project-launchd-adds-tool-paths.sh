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
shim_dir="$tmpdir/shim"
sync_script="$tmpdir/sync.sh"
bootstrap_script="$tmpdir/bootstrap.sh"
supervisor_script="$tmpdir/supervisor.sh"

mkdir -p "$workspace_dir" "$launch_agents_dir" "$log_dir" "$source_home" "$runtime_home" "$profile_dir" "$shim_dir"

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

for path in "$sync_script" "$bootstrap_script" "$supervisor_script"; do
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$path"
done

for tool in node gh openclaw; do
  cat >"$shim_dir/$tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$shim_dir/$tool"
done

PATH="$shim_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
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
bash "$INSTALL_BIN" --profile-id demo >/dev/null

wrapper_path="$workspace_dir/bin/agent-project-demo-launchd.sh"
plist_path="$launch_agents_dir/ai.agent.project.demo.plist"

grep -q "^export ACP_PROJECT_RUNTIME_PATH='.*${shim_dir}.*'$" "$wrapper_path"
grep -q "<string>.*${shim_dir}.*</string>" "$plist_path"

echo "install project launchd adds tool paths test passed"
