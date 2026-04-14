#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/start-pr-fix-worker.sh"
SOURCE_TEMPLATE="${FLOW_ROOT}/tools/templates/pr-fix-template.md"
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
gitea_remote="$tmpdir/gitea.git"
origin_remote="$tmpdir/origin.git"
seed_repo="$tmpdir/seed"
node_bin_dir="$(dirname "$(command -v node)")"
real_git="$(command -v git)"

mkdir -p "$bin_dir" "$template_dir" "$assets_dir" "$profile_dir" "$shim_bin_dir" "$history_root" "$runs_root" "$repo_root" "$worktree_root" "$seed_repo"

cp "$SOURCE_SCRIPT" "$bin_dir/start-pr-fix-worker.sh"
cp "$SOURCE_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$SOURCE_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$SOURCE_TEMPLATE" "$template_dir/pr-fix-template.md"
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
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$repo_root"
  runs_root: "$runs_root"
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
printf 'RUNNER=stub\n'
EOF

cat >"$bin_dir/run-codex-bypass.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'RUNNER=stub\n'
EOF

cat >"$bin_dir/pr-risk.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"risk":"high","riskReason":"paths-outside-low-risk-allowlist:tools/tests/test-package-smoke-command.sh","linkedIssueId":415,"files":["tools/tests/test-package-smoke-command.sh"],"checkFailures":[],"pendingChecks":[],"missingReasons":[]}
JSON
EOF

cat >"$bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shim_bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF

cat >"$shim_bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "$url" in
  http://gitea.test/api/v1/repos/example/repo/pulls/601)
    cat <<'JSON'
{"number":601,"title":"fix: gitea base remote","body":"Closes #415","html_url":"http://gitea.test/example/repo/pulls/601","state":"open","draft":false,"mergeable":true,"requested_reviewers":[],"user":{"login":"acp-admin"},"base":{"ref":"main","sha":"base601"},"head":{"ref":"agent/alpha/issue-415-host-blocker-context","sha":"sha601"}}
JSON
    ;;
  http://gitea.test/api/v1/repos/example/repo/issues/601/comments*)
    cat <<'JSON'
[]
JSON
    ;;
  http://gitea.test/api/v1/repos/example/repo/pulls/601/comments*)
    cat <<'JSON'
{"errors":null,"message":"not found","url":"http://gitea.test/api/swagger"}
JSON
    ;;
  *)
    echo "unexpected curl url: $url" >&2
    exit 1
    ;;
esac
EOF

cat >"$shim_bin_dir/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
for arg in "\$@"; do
  if [[ "\$arg" == "origin/main" || "\$arg" == "origin/main...HEAD" ]]; then
    echo "unexpected origin/main usage: \$*" >&2
    exit 88
  fi
done
exec "$real_git" "\$@"
EOF

chmod +x \
  "$bin_dir/start-pr-fix-worker.sh" \
  "$bin_dir/flow-config-lib.sh" \
  "$bin_dir/flow-shell-lib.sh" \
  "$bin_dir/new-pr-worktree.sh" \
  "$bin_dir/run-codex-safe.sh" \
  "$bin_dir/run-codex-bypass.sh" \
  "$bin_dir/pr-risk.sh" \
  "$bin_dir/agent-github-update-labels" \
  "$shim_bin_dir/tmux" \
  "$shim_bin_dir/curl" \
  "$shim_bin_dir/git"

git init --bare "$gitea_remote" >/dev/null 2>&1
git init --bare "$origin_remote" >/dev/null 2>&1
git init "$seed_repo" >/dev/null 2>&1
git -C "$seed_repo" config user.name "ACP Test"
git -C "$seed_repo" config user.email "acp@example.com"
cat >"$seed_repo/README.md" <<'EOF'
demo
EOF
git -C "$seed_repo" add README.md
git -C "$seed_repo" commit -m "init" >/dev/null
git -C "$seed_repo" branch -M main >/dev/null 2>&1
git -C "$seed_repo" remote add origin "$gitea_remote"
git -C "$seed_repo" push -u origin main >/dev/null 2>&1
git --git-dir="$gitea_remote" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1

git clone "$gitea_remote" "$worktree_root" >/dev/null 2>&1
git -C "$worktree_root" remote rename origin gitea
git -C "$worktree_root" remote add origin "$origin_remote"
git -C "$worktree_root" fetch gitea "+refs/heads/main:refs/remotes/gitea/main" >/dev/null 2>&1
git -C "$worktree_root" checkout -b agent/alpha/issue-415-host-blocker-context >/dev/null 2>&1

worker_output="$(
PATH="$shim_bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROJECT_ID="alpha" \
ACP_FORGE_PROVIDER="gitea" \
ACP_SOURCE_SYNC_REMOTE="gitea" \
ACP_GITEA_BASE_URL="http://gitea.test" \
ACP_GITEA_USERNAME="user" \
ACP_GITEA_PASSWORD="pass" \
F_LOSNING_PR_SESSION_PREFIX="fl-pr-" \
F_LOSNING_AGENT_ROOT="$agent_root" \
F_LOSNING_REPO_SLUG="example/repo" \
F_LOSNING_REPO_ROOT="$repo_root" \
F_LOSNING_DEPENDENCY_SOURCE_ROOT="$repo_root" \
bash "$bin_dir/start-pr-fix-worker.sh" 601 safe fix
)"

grep -q '^SESSION=fl-pr-601$' <<<"$worker_output"
test -f "$runs_root/fl-pr-601/prompt.md"
grep -q 'Base tracking ref: gitea/main' "$runs_root/fl-pr-601/prompt.md"
grep -q 'git diff --stat gitea/main...HEAD' "$runs_root/fl-pr-601/prompt.md"
if grep -q 'unable to compute merge-base' "$runs_root/fl-pr-601/prompt.md"; then
  echo "expected prompt to use gitea/main instead of origin/main" >&2
  exit 1
fi

echo "start-pr-fix-worker source sync remote test passed"
