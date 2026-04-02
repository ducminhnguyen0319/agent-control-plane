#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_WORKER="${FLOW_ROOT}/tools/bin/start-issue-worker.sh"
REAL_POLICY_BIN="${FLOW_ROOT}/tools/bin/issue-requires-local-workspace-install.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
bin_dir="$skill_root/tools/bin"
templates_dir="$skill_root/tools/templates"
assets_dir="$skill_root/assets"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
shim_dir="$tmpdir/shim"
agent_root="$tmpdir/agent"
repo_root="$tmpdir/repo"
capture_dir="$tmpdir/capture"

mkdir -p "$bin_dir" "$templates_dir" "$assets_dir" "$profile_dir" "$shim_dir" "$agent_root" "$repo_root" "$capture_dir"
cp "$REAL_WORKER" "$bin_dir/start-issue-worker.sh"
cp "$REAL_POLICY_BIN" "$bin_dir/issue-requires-local-workspace-install.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$templates_dir/issue-prompt-template.md" <<'EOF'
Issue {ISSUE_ID}
{ISSUE_RECURRING_CONTEXT}
EOF

cat >"$templates_dir/scheduled-issue-prompt-template.md" <<'EOF'
Scheduled issue {ISSUE_ID}
EOF

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$agent_root"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$repo_root"
  runs_root: "$agent_root/runs"
  state_root: "$agent_root/state"
  retained_repo_root: "$repo_root"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
  issue_branch_prefix: "agent/demo/issue"
  pr_worktree_branch_prefix: "agent/demo/pr"
  managed_pr_branch_globs: "agent/demo/* codex/* openclaw/*"
execution:
  coding_worker: "codex"
  resident_workers:
    issue_reuse_enabled: true
    issue_max_tasks_per_worker: 12
    issue_max_age_seconds: 86400
EOF

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test"
git -C "$repo_root" config user.email "test@example.com"
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1

cat >"$shim_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$shim_dir/tmux"

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  if [[ "${3:-}" == "--jq" ]]; then
    printf '5000\n'
    exit 0
  fi
  cat <<'JSON'
{"resources":{"graphql":{"remaining":5000}}}
JSON
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Recurring issue ${issue_id}","body":"Keep this recurring issue moving.","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-keep-open"}],"comments":[{"body":"Completed another dependency-audit reduction cycle.\\n\\nWhat changed:\\n- Updated Next.js to a patched release.\\n- Refreshed lockfile."},{"body":"Blocked on external network access for the dependency-audit slice.\\n\\nTarget: React / React DOM\\nWhy now: advisory still mentions 19.1.0."}]}
JSON
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi
exit 64
EOF
chmod +x "$shim_dir/gh"

cat >"$bin_dir/new-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issue_id="${1:?issue id required}"
worktree="${TEST_CAPTURE_DIR:?}/worktree-${issue_id}"
mkdir -p "$worktree"
if [[ ! -d "$worktree/.git" ]]; then
  git -C "$worktree" init -b main >/dev/null 2>&1
  git -C "$worktree" config user.name "Test"
  git -C "$worktree" config user.email "test@example.com"
  printf 'stub\n' >"$worktree/README.md"
  git -C "$worktree" add README.md
  git -C "$worktree" commit -m "init" >/dev/null 2>&1
fi
printf 'WORKTREE=%s\n' "$worktree"
printf 'BRANCH=agent/demo/issue-%s-test\n' "$issue_id"
EOF
chmod +x "$bin_dir/new-worktree.sh"

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/run-codex-safe.sh"

PATH="$shim_dir:$PATH" ACP_PROJECT_ID="demo" ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" TEST_CAPTURE_DIR="$capture_dir" bash "$bin_dir/start-issue-worker.sh" 613 >/dev/null

prompt_file="$agent_root/runs/demo-issue-613/prompt.md"
grep -q '### Recent cycle notes from issue comments' "$prompt_file"
grep -q 'Completed another dependency-audit reduction cycle' "$prompt_file"
grep -q 'Blocked on external network access for the dependency-audit slice' "$prompt_file"
grep -q 'Prefer the recent cycle notes below over repeating broad web research' "$prompt_file"

echo "start issue worker recurring context includes cycle notes test passed"
