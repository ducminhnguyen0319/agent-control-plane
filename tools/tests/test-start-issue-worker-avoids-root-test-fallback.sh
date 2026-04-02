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

mkdir -p "$bin_dir" "$templates_dir" "$assets_dir" "$profile_dir" "$shim_dir" "$agent_root" "$repo_root"
cp "$REAL_WORKER" "$bin_dir/start-issue-worker.sh"
cp "$REAL_POLICY_BIN" "$bin_dir/issue-requires-local-workspace-install.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

cat >"$templates_dir/issue-prompt-template.md" <<'EOF'
## Verify
```bash
{ISSUE_VERIFICATION_COMMAND_SNIPPET}
```
EOF

cat >"$templates_dir/scheduled-issue-prompt-template.md" <<'EOF'
SCHEDULED
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
  safe_profile: "demo_safe"
  bypass_profile: "demo_bypass"
EOF

cat >"$repo_root/package.json" <<'EOF'
{
  "name": "demo-repo",
  "private": true,
  "scripts": {
    "test": "node --test"
  }
}
EOF

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
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Focused verification issue ${issue_id}","body":"Keep this cycle focused on one narrow slice.","url":"https://example.test/issues/${issue_id}","labels":[],"comments":[]}
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
  git -C "$worktree" config user.name "Codex"
  git -C "$worktree" config user.email "codex@example.com"
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

capture_dir="$tmpdir/case"
mkdir -p "$capture_dir"

PATH="$shim_dir:$PATH" ACP_PROJECT_ID="demo" ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" TEST_CAPTURE_DIR="$capture_dir" bash "$bin_dir/start-issue-worker.sh" 42 >/dev/null

prompt_file="$agent_root/runs/demo-issue-42/prompt.md"

grep -q 'Pick the narrowest relevant local verification' "$prompt_file"
grep -q 'Do not default to repo-wide pnpm test' "$prompt_file"
grep -q '@<repo>/api test' "$prompt_file"
if grep -q '^pnpm test$' "$prompt_file"; then
  echo "root pnpm test fallback unexpectedly rendered" >&2
  exit 1
fi

echo "start issue worker avoids root test fallback test passed"
