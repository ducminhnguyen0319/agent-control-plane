#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_SCRIPT="${FLOW_ROOT}/tools/bin/audit-agent-worktrees.sh"
CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
agent_root="$tmpdir/agent"
bin_dir="$tmpdir/bin"

mkdir -p "$repo_root" "$worktree_root" "$agent_root/runs/fl-issue-250" "$agent_root/state/pending-launches" "$bin_dir"
repo_root="$(cd "$repo_root" && pwd -P)"
worktree_root="$(cd "$worktree_root" && pwd -P)"
agent_root="$(cd "$agent_root" && pwd -P)"
bin_dir="$(cd "$bin_dir" && pwd -P)"

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Codex"
git -C "$repo_root" config user.email "codex@example.com"
printf 'root\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1

worktree_path="$worktree_root/issue-250-unreconciled-owner"
git -C "$repo_root" worktree add -b "agent/acp/issue-250-unreconciled-owner" "$worktree_path" main >/dev/null 2>&1
worktree_path="$(cd "$worktree_path" && pwd -P)"

cp "$AUDIT_SCRIPT" "$bin_dir/audit-agent-worktrees.sh"
cp "$CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
chmod +x "$bin_dir/audit-agent-worktrees.sh"
chmod +x "$bin_dir/flow-config-lib.sh" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/agent-project-worker-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'STATUS=SUCCEEDED\n'
EOF
chmod +x "$bin_dir/agent-project-worker-status"

cat >"$bin_dir/agent-cleanup-worktree" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "cleanup should not be called for unreconciled owner" >&2
exit 99
EOF
chmod +x "$bin_dir/agent-cleanup-worktree"

mkdir -p "$agent_root/runs/acp-issue-250"
cat >"$agent_root/runs/acp-issue-250/run.env" <<EOF
SESSION=acp-issue-250
WORKTREE=$worktree_path
BRANCH=agent/acp/issue-250-unreconciled-owner
EOF

output="$(
  ACP_ISSUE_SESSION_PREFIX="acp-issue-" \
  ACP_PR_SESSION_PREFIX="acp-pr-" \
  ACP_ISSUE_BRANCH_PREFIX="agent/acp/issue" \
  ACP_MANAGED_PR_BRANCH_GLOBS="agent/acp/* codex/* openclaw/*" \
  F_LOSNING_AGENT_REPO_ROOT="$repo_root" \
  F_LOSNING_WORKTREE_ROOT="$worktree_root" \
  F_LOSNING_AGENT_ROOT="$agent_root" \
  bash "$bin_dir/audit-agent-worktrees.sh" --cleanup
)"

grep -q '^LEGACY_AGENT_WORKTREE_COUNT=0$' <<<"$output"
test -d "$worktree_path"

echo "audit agent worktrees unreconciled owner test passed"
