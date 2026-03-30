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
origin_repo="$tmpdir/origin.git"
node_bin_dir="$(dirname "$(command -v node)")"

mkdir -p "$bin_dir" "$template_dir" "$assets_dir" "$profile_dir" "$shim_bin_dir" "$history_root" "$runs_root" "$repo_root" "$worktree_root"

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
  worktree_root: "$worktree_root"
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
  openclaw:
    model: "openrouter/stepfun/step-3.5-flash:free"
    thinking: "minimal"
    timeout_seconds: 600
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
{"risk":"high","riskReason":"paths-outside-low-risk-allowlist:apps/api/src/modules/auth/auth.service.ts","linkedIssueId":415,"files":["apps/api/src/modules/auth/auth.service.extended.spec.ts","apps/api/src/modules/auth/auth.service.ts","apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts","apps/web/src/app/(auth)/login/page.spec.tsx","apps/web/src/app/(auth)/login/page.tsx"],"checkFailures":[],"pendingChecks":[],"missingReasons":["agent-status-blocker-present"]}
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
{"number":601,"title":"fix(auth): carry host verification blocker into prompt","body":"Closes #415","url":"https://example.test/pr/601","headRefName":"agent/alpha/issue-415-host-blocker-context","baseRefName":"main","mergeStateStatus":"CLEAN","statusCheckRollup":[],"labels":[{"name":"agent-repair-queued"}],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  case "${2:-}" in
    repos/example/repo/pulls/601)
      cat <<'JSON'
{"head":{"sha":"sha601"},"mergeable":true}
JSON
      exit 0
      ;;
    repos/example/repo/pulls/601/comments)
      printf '[]\n'
      exit 0
      ;;
    repos/example/repo/issues/601/comments)
      printf '[]\n'
      exit 0
      ;;
  esac
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
  "$bin_dir/start-pr-fix-worker.sh" \
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

mkdir -p \
  "$worktree_root/apps/api/src/modules/auth" \
  "$worktree_root/apps/web/e2e/archive/auth" \
  "$worktree_root/apps/web/src/app/(auth)/login"

cat >"$worktree_root/apps/api/src/modules/auth/auth.service.ts" <<'EOF'
export const loginFailureMode = 'legacy';
EOF

cat >"$worktree_root/apps/api/src/modules/auth/auth.service.extended.spec.ts" <<'EOF'
describe('auth service', () => {
  it('handles login failures', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$worktree_root/apps/web/src/app/(auth)/login/page.tsx" <<'EOF'
export default function LoginPage() {
  return null
}
EOF

cat >"$worktree_root/apps/web/src/app/(auth)/login/page.spec.tsx" <<'EOF'
describe('login page', () => {
  it('renders', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$worktree_root/apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts" <<'EOF'
test('tenant isolation login', async () => {
  expect(true).toBeTruthy()
})
EOF

git -C "$worktree_root" add .
git -C "$worktree_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$worktree_root" branch -M main >/dev/null 2>&1
git -C "$worktree_root" push origin main >/dev/null 2>&1
git -C "$worktree_root" checkout -b agent/alpha/issue-415-host-blocker-context >/dev/null 2>&1

cat >"$worktree_root/apps/api/src/modules/auth/auth.service.ts" <<'EOF'
export const loginFailureMode = 'generic-invalid-credentials';
EOF

cat >"$worktree_root/apps/api/src/modules/auth/auth.service.extended.spec.ts" <<'EOF'
describe('auth service', () => {
  it('normalizes tenant login failures', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$worktree_root/apps/web/src/app/(auth)/login/page.tsx" <<'EOF'
export default function LoginPage() {
  return 'Invalid credentials'
}
EOF

cat >"$worktree_root/apps/web/src/app/(auth)/login/page.spec.tsx" <<'EOF'
describe('login page', () => {
  it('shows the generic invalid credentials message', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$worktree_root/apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts" <<'EOF'
test('tenant isolation login hides tenant existence', async () => {
  expect(true).toBeTruthy()
})
EOF

git -C "$worktree_root" add .
git -C "$worktree_root" -c user.name=Test -c user.email=test@example.com commit -m "pr changes" >/dev/null

mkdir -p "$history_root/fl-pr-601-20260316-000001"
cat >"$history_root/fl-pr-601-20260316-000001/host-blocker.md" <<'EOF'
Verification guard blocked branch publication.

Why it was blocked:
- missing API typecheck or repo typecheck for API changes
- missing Web verification command for web changes
EOF

worker_output="$(
PATH="$shim_bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROJECT_ID="alpha" \
ACP_PR_SESSION_PREFIX="fl-pr-" \
F_LOSNING_PR_SESSION_PREFIX="fl-pr-" \
F_LOSNING_AGENT_ROOT="$agent_root" \
F_LOSNING_REPO_SLUG="example/repo" \
F_LOSNING_REPO_ROOT="$repo_root" \
F_LOSNING_DEPENDENCY_SOURCE_ROOT="$repo_root" \
bash "$bin_dir/start-pr-fix-worker.sh" 601 safe fix
)"

prompt_file="$(awk -F= '/^PROMPT=/{print $2}' <<<"$worker_output")"
test -n "$prompt_file"
test -f "$prompt_file"

grep -Fq 'Current host-side publish blocker summary:' "$prompt_file"
grep -Fq 'Verification guard blocked branch publication.' "$prompt_file"
grep -Fq 'missing API typecheck or repo typecheck for API changes' "$prompt_file"
grep -Fq 'Required targeted verification coverage before `updated-branch`:' "$prompt_file"
grep -Fq 'apps/api/src/modules/auth/auth.service.extended.spec.ts' "$prompt_file"
grep -Fq 'apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts' "$prompt_file"
grep -Fq 'Pre-approved local verification fallbacks:' "$prompt_file"
grep -Fq 'loopback retry command:' "$prompt_file"
grep -Fq 'playwright test e2e/archive/auth/tenant-isolation-login.spec.ts --project=chromium' "$prompt_file"
grep -Fq 'Do not ask the user for clarification, approval, or a next-step choice from inside the worker.' "$prompt_file"

echo "start-pr-fix-worker host blocker context test passed"
