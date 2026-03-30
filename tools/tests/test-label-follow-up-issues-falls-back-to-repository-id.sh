#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_root="$tmpdir/workspace"
adapter_bin_dir="$workspace_root/bin"
tools_bin_dir="$workspace_root/tools/bin"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/demo"
agent_root="$tmpdir/agent"
repo_root="$tmpdir/repo"
shim_dir="$tmpdir/shim"
run_dir="$agent_root/runs/demo-issue-42"
capture_file="$tmpdir/labels.log"

mkdir -p "$adapter_bin_dir" "$tools_bin_dir" "$profile_dir" "$agent_root/runs" "$agent_root/history" "$agent_root/state" "$repo_root" "$shim_dir" "$run_dir"

cp "$FLOW_ROOT/bin/label-follow-up-issues.sh" "$adapter_bin_dir/label-follow-up-issues.sh"
cp "$FLOW_ROOT/tools/bin/flow-config-lib.sh" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_ROOT/tools/bin/flow-shell-lib.sh" "$tools_bin_dir/flow-shell-lib.sh"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  id: "123"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$agent_root"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$repo_root"
  runs_root: "$agent_root/runs"
  state_root: "$agent_root/state"
  history_root: "$agent_root/history"
  retained_repo_root: "$repo_root"
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

cat >"$tools_bin_dir/agent-project-worker-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${TEST_RUN_DIR:?}/run.env
OUT
EOF
chmod +x "$tools_bin_dir/agent-project-worker-status"

cat >"$tools_bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_CAPTURE_FILE:?}"
EOF
chmod +x "$tools_bin_dir/agent-github-update-labels"

cat >"$adapter_bin_dir/issue-resource-class.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
IS_E2E=yes
OUT
EOF
chmod +x "$adapter_bin_dir/issue-resource-class.sh"

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"state":"OPEN","title":"Follow-up issue ${issue_id}","body":"Keep this focused.","url":"https://example.test/issues/${issue_id}","labels":[],"comments":[],"createdAt":"2026-03-28T20:00:00Z","updatedAt":"2026-03-28T20:00:00Z"}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  case "${route}" in
    repos/example/demo/issues/42/comments*)
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
      ;;
    repositories/123/issues/42/comments*)
      cat <<'JSON'
[{"user":{"login":"tester"},"created_at":"2026-03-28T20:01:00Z","body":"Please follow up in issue #77."}]
JSON
      exit 0
      ;;
  esac
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$shim_dir/gh"

cat >"$run_dir/run.env" <<'EOF'
ISSUE_ID=42
SESSION=demo-issue-42
STARTED_AT=2026-03-28T20:00:00Z
EOF

out="$(
  PATH="$shim_dir:$PATH" \
  ACP_PROJECT_ID="demo" \
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  TEST_RUN_DIR="$run_dir" \
  TEST_CAPTURE_FILE="$capture_file" \
  GITHUB_ACTOR="tester" \
  bash "$adapter_bin_dir/label-follow-up-issues.sh" demo-issue-42
)"

grep -q '^LABELED=77$' <<<"$out"
grep -q '^COUNT=1$' <<<"$out"
grep -q -- '--repo-slug example/demo --number 77 --add agent-e2e-heavy' "$capture_file"

echo "label follow-up issues repository id fallback test passed"
