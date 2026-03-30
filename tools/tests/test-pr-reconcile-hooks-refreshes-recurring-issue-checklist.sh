#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
hooks_dir="$skill_root/hooks"
tools_bin_dir="$skill_root/tools/bin"
adapter_bin_dir="$skill_root/bin"
assets_dir="$skill_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
shim_dir="$tmpdir/shim"

mkdir -p "$hooks_dir" "$tools_bin_dir" "$adapter_bin_dir" "$assets_dir" "$profile_dir" "$shim_dir"

cp "$FLOW_ROOT/hooks/pr-reconcile-hooks.sh" "$hooks_dir/pr-reconcile-hooks.sh"
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
  coding_worker: "openclaw"
EOF

printf '# demo skill\n' >"$skill_root/SKILL.md"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$adapter_bin_dir/pr-risk.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<JSON
{"linkedIssueId":"42","isManagedByAgent":true}
JSON
EOF
chmod +x "$adapter_bin_dir/pr-risk.sh"

sync_invocation_file="$tmpdir/sync-invocation.txt"
cat >"$tools_bin_dir/sync-recurring-issue-checklist.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_SYNC_INVOCATION_FILE:?}"
exit 0
EOF
chmod +x "$tools_bin_dir/sync-recurring-issue-checklist.sh"

cat >"$tools_bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$tools_bin_dir/agent-github-update-labels"

cat >"$tools_bin_dir/kick-scheduler.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$tools_bin_dir/kick-scheduler.sh"

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":42,"state":"OPEN","title":"Recurring demo issue","body":"Keep it open.","url":"https://example.test/issues/42","labels":[{"name":"agent-keep-open"}],"comments":[],"createdAt":"2026-03-28T10:00:00Z","updatedAt":"2026-03-28T10:00:00Z"}
JSON
  exit 0
fi
echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$shim_dir/gh"

export PATH="$shim_dir:$PATH"
export ACP_PROJECT_ID="demo"
export ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root"
export TEST_SYNC_INVOCATION_FILE="$sync_invocation_file"
source "$hooks_dir/pr-reconcile-hooks.sh"

pr_after_merged 99

test -f "$sync_invocation_file"
grep -q -- '--repo-slug example/demo --issue-id 42' "$sync_invocation_file"

echo "pr reconcile hooks recurring checklist refresh test passed"
