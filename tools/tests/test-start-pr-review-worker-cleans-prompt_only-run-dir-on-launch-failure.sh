#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/start-pr-review-worker.sh"
SOURCE_TEMPLATE="${FLOW_ROOT}/tools/templates/pr-review-template.md"
SOURCE_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
SOURCE_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_root="$tmpdir/workspace/tools"
bin_dir="$workspace_root/bin"
template_dir="$workspace_root/templates"
assets_dir="$workspace_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/alpha"
shim_bin_dir="$tmpdir/shims"
agent_root="$tmpdir/agent-root"
history_root="$agent_root/history"
runs_root="$agent_root/runs"
repo_root="$tmpdir/repo-root"
worktree_root="$tmpdir/worktree"
origin_repo="$tmpdir/origin.git"

mkdir -p "$bin_dir" "$template_dir" "$assets_dir" "$profile_dir" "$shim_bin_dir" "$history_root" "$runs_root" "$repo_root" "$worktree_root"

cp "$SOURCE_SCRIPT" "$bin_dir/start-pr-review-worker.sh"
cp "$SOURCE_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$SOURCE_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$SOURCE_TEMPLATE" "$template_dir/pr-review-template.md"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "alpha"
repo:
  slug: "example/repo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$agent_root"
  worktree_root: "$worktree_root"
  agent_repo_root: "$repo_root"
  runs_root: "$runs_root"
  history_root: "$history_root"
  state_root: "$agent_root/state"
  retained_repo_root: "$repo_root"
  vscode_workspace_file: "$tmpdir/alpha.code-workspace"
session_naming:
  issue_prefix: "fl-issue-"
  pr_prefix: "fl-pr-"
  issue_branch_prefix: "agent/alpha/issue"
  pr_worktree_branch_prefix: "agent/alpha/pr"
  managed_pr_branch_globs: "agent/alpha/* codex/* openclaw/*"
execution:
  coding_worker: "codex"
  safe_profile: "mock-safe"
  bypass_profile: "mock-bypass"
  verification:
    web_playwright_command: "pnpm exec playwright test"
  review_requires_independent_final_review: true
EOF

cat >"$bin_dir/new-pr-worktree.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'WORKTREE=%s\n' "$worktree_root"
EOF

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 97
EOF

cat >"$bin_dir/run-codex-bypass.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 97
EOF

cat >"$bin_dir/pr-risk.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"risk":"medium","riskReason":"review","agentLane":"double-check-1","currentDoubleCheckStage":1,"linkedIssueId":415,"checksBypassed":false,"files":["README.md"]}
JSON
EOF

cat >"$bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shim_bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":601,"title":"docs: review cleanup","body":"","url":"https://example.test/pr/601","headRefName":"agent/alpha/issue-415-review-cleanup","baseRefName":"main","mergeStateStatus":"CLEAN","statusCheckRollup":[],"labels":[{"name":"agent-review"}],"comments":[]}
JSON
  exit 0
fi
echo "unexpected gh args: $*" >&2
exit 1
EOF

cat >"$shim_bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF

chmod +x \
  "$bin_dir/start-pr-review-worker.sh" \
  "$bin_dir/flow-config-lib.sh" \
  "$bin_dir/flow-shell-lib.sh" \
  "$bin_dir/new-pr-worktree.sh" \
  "$bin_dir/run-codex-safe.sh" \
  "$bin_dir/run-codex-bypass.sh" \
  "$bin_dir/pr-risk.sh" \
  "$bin_dir/agent-github-update-labels" \
  "$shim_bin_dir/gh" \
  "$shim_bin_dir/tmux"

git init --bare "$origin_repo" >/dev/null 2>&1
git clone "$origin_repo" "$worktree_root" >/dev/null 2>&1
cat >"$worktree_root/README.md" <<'EOF'
# demo
EOF
git -C "$worktree_root" add README.md
git -C "$worktree_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$worktree_root" branch -M main >/dev/null 2>&1
git -C "$worktree_root" push origin main >/dev/null 2>&1
git -C "$worktree_root" checkout -b agent/alpha/issue-415-review-cleanup >/dev/null 2>&1

set +e
PATH="$shim_bin_dir:$PATH" \
ACP_PROJECT_ID="alpha" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
bash "$bin_dir/start-pr-review-worker.sh" 601 safe >/dev/null 2>&1
status=$?
set -e

test "$status" -ne 0
test ! -d "$runs_root/fl-pr-601"

echo "start pr review worker launch-failure cleanup test passed"
