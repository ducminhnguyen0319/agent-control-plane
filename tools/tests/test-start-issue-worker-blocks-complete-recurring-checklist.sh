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
Issue {ISSUE_ID}: {ISSUE_TITLE}
EOF

cat >"$templates_dir/scheduled-issue-prompt-template.md" <<'EOF'
Scheduled issue {ISSUE_ID}: {ISSUE_TITLE}
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
  coding_worker: "codex"
  resident_workers:
    issue_reuse_enabled: true
    issue_max_tasks_per_worker: 12
    issue_max_age_seconds: 86400
EOF

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Resident"
git -C "$repo_root" config user.email "resident@example.com"
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

capture_dir="${TEST_CAPTURE_DIR:?}"

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Recurring issue ${issue_id}","body":"Keep it moving.\n\nChecklist:\n- [x] Ship the first improvement.\n- [x] Ship the second improvement.\n","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-keep-open"}],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  shift
  route="${1:-}"
  shift || true
  method="GET"
  body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --method)
        method="${2:-GET}"
        shift 2
        ;;
      -f|--field|--raw-field)
        field="${2:-}"
        if [[ "$field" == body=* ]]; then
          body="${field#body=}"
        fi
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "$method" == "POST" && "$route" == *"/issues/"*"/comments" ]]; then
    printf '%s' "$body" >"$capture_dir/comment.md"
    exit 0
  fi
fi

exit 64
EOF
chmod +x "$shim_dir/gh"

cat >"$bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_CAPTURE_DIR:?}/labels.log"
EOF
chmod +x "$bin_dir/agent-github-update-labels"

cat >"$bin_dir/sync-recurring-issue-checklist.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_CAPTURE_DIR:?}/sync.log"
cat <<OUT
STATUS=updated
CHECKLIST_TOTAL=2
CHECKLIST_UNCHECKED=0
CHECKLIST_MATCHED_PR_NUMBERS=11,12
OUT
EOF
chmod +x "$bin_dir/sync-recurring-issue-checklist.sh"

cat >"$bin_dir/new-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "new-worktree should not run" >&2
exit 99
EOF
chmod +x "$bin_dir/new-worktree.sh"

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "run-codex-safe should not run" >&2
exit 99
EOF
chmod +x "$bin_dir/run-codex-safe.sh"

PATH="$shim_dir:$PATH" \
ACP_PROJECT_ID="demo" \
ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
TEST_CAPTURE_DIR="$capture_dir" \
bash "$bin_dir/start-issue-worker.sh" 42 >/dev/null

run_dir="$agent_root/runs/demo-issue-42"

test ! -d "$run_dir"
test -f "$capture_dir/sync.log"
grep -q -- '--repo-slug example/demo --issue-id 42' "$capture_dir/sync.log"
test -f "$capture_dir/comment.md"
grep -q '^# Blocker: All checklist items already completed$' "$capture_dir/comment.md"
grep -q '^Recently matched PRs: #11, #12$' "$capture_dir/comment.md"
grep -q -- '--repo-slug example/demo --number 42 --add agent-blocked --remove agent-running' "$capture_dir/labels.log"

echo "start issue worker blocks completed recurring checklist test passed"
