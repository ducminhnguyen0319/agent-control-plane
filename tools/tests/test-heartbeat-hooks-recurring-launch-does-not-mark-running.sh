#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_HOOKS="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
hooks_dir="$skill_root/hooks"
bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
shim_dir="$tmpdir/shim"
capture_file="$tmpdir/capture.log"
labels_log="$tmpdir/labels.log"

mkdir -p "$hooks_dir" "$bin_dir" "$assets_dir" "$profile_dir" "$shim_dir"
cp "$REAL_HOOKS" "$hooks_dir/heartbeat-hooks.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/agent"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$tmpdir/agent/runs"
  state_root: "$tmpdir/agent/state"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
execution:
  coding_worker: "openclaw"
  resident_workers:
    issue_reuse_enabled: true
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
  issue_branch_prefix: "agent/demo/issue"
  pr_worktree_branch_prefix: "agent/demo/pr"
EOF

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Resident issue ${issue_id}","body":"Keep going.","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-keep-open"}],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  printf '[]\n'
  exit 0
fi

exit 64
EOF
chmod +x "$shim_dir/gh"

cat >"$bin_dir/agent-project-detached-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_CAPTURE_FILE:?}"
printf 'LAUNCH_MODE=detached\n'
EOF

cat >"$bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_LABELS_LOG:?}"
EOF

chmod +x "$bin_dir/agent-project-detached-launch" "$bin_dir/agent-github-update-labels"

PATH="$shim_dir:$PATH" \
FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_FILE="$capture_file" \
TEST_LABELS_LOG="$labels_log" \
bash -c '
  set -euo pipefail
  source "'"$hooks_dir"'/heartbeat-hooks.sh"
  heartbeat_start_issue_worker 440 >/dev/null
'

grep -q 'start-resident-issue-loop.sh 440' "$capture_file"
if [[ -s "$labels_log" ]]; then
  echo "recurring launch should not update labels during heartbeat dispatch" >&2
  cat "$labels_log" >&2
  exit 1
fi

echo "heartbeat hooks recurring launch avoids premature running label test passed"
