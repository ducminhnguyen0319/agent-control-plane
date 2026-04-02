#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_REUSE="${FLOW_ROOT}/tools/bin/reuse-issue-worktree.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
bin_dir="$skill_root/tools/bin"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
origin_repo="$tmpdir/origin.git"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
worktree_path="$worktree_root/issue-440"
shim_dir="$tmpdir/shim"

mkdir -p "$bin_dir" "$profile_dir" "$worktree_root" "$shim_dir"
cp "$REAL_REUSE" "$bin_dir/reuse-issue-worktree.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/prepare-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/prepare-worktree.sh"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/agent"
  worktree_root: "$worktree_root"
  agent_repo_root: "$repo_root"
  runs_root: "$tmpdir/agent/runs"
  state_root: "$tmpdir/agent/state"
  history_root: "$tmpdir/agent/history"
  retained_repo_root: "$repo_root"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
  issue_branch_prefix: "agent/demo/issue"
  pr_worktree_branch_prefix: "agent/demo/pr"
  managed_pr_branch_globs: "agent/demo/* codex/* openclaw/*"
EOF

git init --bare --initial-branch=main "$origin_repo" >/dev/null 2>&1
git clone "$origin_repo" "$repo_root" >/dev/null 2>&1
git -C "$repo_root" config user.name "Resident"
git -C "$repo_root" config user.email "resident@example.com"
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1
git -C "$repo_root" push -u origin main >/dev/null 2>&1
git -C "$repo_root" worktree add -b "agent/demo/issue-440-old" "$worktree_path" origin/main >/dev/null 2>&1

real_git="$(command -v git)"
cat >"$shim_dir/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "-C" && "\${2:-}" == "$worktree_path" && "\${3:-}" == "branch" && "\${4:-}" == "--show-current" ]]; then
  printf 'agent/demo/issue-440-old\n'
  exit 0
fi
exec "$real_git" "\$@"
EOF
chmod +x "$shim_dir/git"

set +e
PATH="$shim_dir:$PATH" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROFILE_ID="demo" \
bash "$bin_dir/reuse-issue-worktree.sh" "$worktree_path" 441 "branch-check" \
  >"$tmpdir/stdout.log" 2>"$tmpdir/stderr.log"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "expected reuse-issue-worktree.sh to reject mismatched post-checkout branch" >&2
  exit 1
fi

grep -q '^reused worktree branch mismatch: expected agent/demo/issue-441-branch-check-' "$tmpdir/stderr.log"

echo "reuse issue worktree validates post checkout branch test passed"
