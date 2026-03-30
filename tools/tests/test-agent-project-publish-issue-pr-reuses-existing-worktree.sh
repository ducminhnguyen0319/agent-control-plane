#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-publish-issue-pr"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_bin_dir="$tmpdir/workspace/bin"
shared_home="$tmpdir/shared-home"
flow_root="$shared_home/skills/openclaw/agent-control-plane"
flow_assets_dir="$flow_root/assets"
profile_registry_root="$tmpdir/profile-registry"
flow_profiles_dir="$profile_registry_root/demo"
repo_root="$tmpdir/repo"
origin_root="$tmpdir/origin.git"
worktree_root="$tmpdir/worktrees"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
session="demo-issue-10"
archive_dir="$history_root/${session}-20260326-000000"
bin_dir="$tmpdir/bin"
shared_bin="$tmpdir/tools/bin"

mkdir -p "$workspace_bin_dir" "$flow_assets_dir" "$flow_profiles_dir" "$repo_root" "$worktree_root" "$runs_root" "$history_root" "$bin_dir" "$shared_bin" "$archive_dir"
cp "$SOURCE_SCRIPT" "$workspace_bin_dir/agent-project-publish-issue-pr"
cp "$FLOW_CONFIG_LIB" "$workspace_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$workspace_bin_dir/flow-shell-lib.sh"
printf 'skill root\n' >"$flow_root/SKILL.md"
printf '{}\n' >"$flow_assets_dir/workflow-catalog.json"

cat >"$flow_profiles_dir/control-plane.yaml" <<EOF_PROFILE
id: "demo"
repo:
  slug: "example/repo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/agent-root"
  agent_repo_root: "$repo_root"
  worktree_root: "$worktree_root"
  runs_root: "$runs_root"
  history_root: "$history_root"
EOF_PROFILE

cat >"$shared_bin/agent-project-worker-status" <<EOF_STATUS
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=%s\n' "$session"
printf 'STATUS=UNKNOWN\n'
EOF_STATUS

cat >"$shared_bin/issue-publish-scope-guard.sh" <<'EOF_SCOPE'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_SCOPE

cat >"$shared_bin/branch-verification-guard.sh" <<'EOF_VERIFY'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_VERIFY

cat >"$bin_dir/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}:${2:-}" in
  issue:view)
    printf '{"title":"Existing worktree issue","url":"https://github.com/example/repo/issues/10","labels":[]}'
    ;;
  pr:list)
    printf '[]\n'
    ;;
  api:user)
    printf 'tester\n'
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
EOF_GH

chmod +x \
  "$workspace_bin_dir/agent-project-publish-issue-pr" \
  "$workspace_bin_dir/flow-config-lib.sh" \
  "$workspace_bin_dir/flow-shell-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/issue-publish-scope-guard.sh" \
  "$shared_bin/branch-verification-guard.sh" \
  "$bin_dir/gh"

git init --bare "$origin_root" >/dev/null 2>&1
git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test"
git -C "$repo_root" config user.email "test@example.com"
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1
git -C "$repo_root" remote add origin "$origin_root"
git -C "$repo_root" push -u origin main >/dev/null 2>&1

branch_name="agent/demo/issue-10-existing-worktree"
git -C "$repo_root" branch "$branch_name" main
existing_worktree="$worktree_root/existing"
git -C "$repo_root" worktree add "$existing_worktree" "$branch_name" >/dev/null 2>&1
printf 'existing\n' >>"$existing_worktree/README.md"
git -C "$existing_worktree" add README.md
git -C "$existing_worktree" commit -m "feat: existing worktree recovery" >/dev/null 2>&1
final_head="$(git -C "$existing_worktree" rev-parse HEAD)"
existing_worktree_canonical="$(cd "$existing_worktree" && pwd -P)"

cat >"$archive_dir/run.env" <<EOF_RUN
ISSUE_ID=10
BRANCH=$branch_name
WORKTREE=$tmpdir/missing-worktree
FINAL_HEAD=$final_head
EOF_RUN

printf '{"status":"pass","command":"npm test"}\n' >"$archive_dir/verification.jsonl"

output="$(PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  SHARED_AGENT_HOME="$shared_home" \
  ACP_ROOT="$flow_root" \
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  ACP_PROJECT_ID="demo" \
  AGENT_PROJECT_ID="demo" \
  AGENT_CONTROL_PLANE_CONFIG="$flow_profiles_dir/control-plane.yaml" \
  ACP_CONFIG="$flow_profiles_dir/control-plane.yaml" \
  bash "$workspace_bin_dir/agent-project-publish-issue-pr" \
    --repo-slug example/repo \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --session "$session" \
    --dry-run 2>&1)"

grep -q '^PUBLISH_STATUS=would-create-pr$' <<<"$output"
grep -q 'WORKTREE_RECOVERY=reused-existing' <<<"$output"
grep -q "RECOVERY_WORKTREE=$existing_worktree_canonical" <<<"$output"
grep -q '^PR_TITLE=feat: existing worktree recovery$' <<<"$output"

echo "agent-project publish issue PR reuses existing worktree test passed"
