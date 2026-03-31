#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
hooks_dir="$skill_root/hooks"
tools_bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"

mkdir -p "$hooks_dir" "$tools_bin_dir" "$assets_dir" "$profile_dir"

cp "$FLOW_ROOT/hooks/issue-reconcile-hooks.sh" "$hooks_dir/issue-reconcile-hooks.sh"
cp "$FLOW_ROOT/tools/bin/flow-config-lib.sh" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_ROOT/tools/bin/flow-shell-lib.sh" "$tools_bin_dir/flow-shell-lib.sh"

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
  runs_root: "$tmpdir/runs"
  state_root: "$tmpdir/state"
  history_root: "$tmpdir/history"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
  issue_branch_prefix: "agent/demo/issue"
  pr_worktree_branch_prefix: "agent/demo/pr"
  managed_pr_branch_globs: "agent/demo/*"
execution:
  coding_worker: "claude"
EOF

printf '# demo skill\n' >"$skill_root/SKILL.md"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

kick_invocation_file="$tmpdir/kick-invocation.txt"
cat >"$tools_bin_dir/kick-scheduler.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'profile=%s delay=%s\n' "${ACP_PROJECT_ID:-}" "${1:-}" >"${TEST_KICK_INVOCATION_FILE:?}"
EOF
chmod +x "$tools_bin_dir/kick-scheduler.sh"

cat >"$tools_bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$tools_bin_dir/agent-github-update-labels"

export ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root"
export TEST_KICK_INVOCATION_FILE="$kick_invocation_file"
export ISSUE_ID=42
source "$hooks_dir/issue-reconcile-hooks.sh"

issue_after_reconciled FAILED "" "" ""

test -f "$kick_invocation_file"
grep -q '^profile=demo delay=2$' "$kick_invocation_file"

echo "issue reconcile hooks kick scheduler uses resolved profile test passed"
