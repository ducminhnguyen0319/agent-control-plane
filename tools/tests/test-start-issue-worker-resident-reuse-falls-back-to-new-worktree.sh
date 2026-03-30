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
{ISSUE_RECURRING_CONTEXT}
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
  managed_pr_branch_globs: "agent/demo/* codex/* openclaw/*"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "openrouter/stepfun/step-3.5-flash:free"
    thinking: "minimal"
    timeout_seconds: 600
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
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Resident issue ${issue_id}","body":"Keep this issue moving.","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-keep-open"}],"comments":[]}
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
capture_dir="${TEST_CAPTURE_DIR:?}"
worktree="${capture_dir}/worktree-${issue_id}"
mkdir -p "$capture_dir" "$worktree"
if [[ ! -d "$worktree/.git" ]]; then
  git -C "$worktree" init -b main >/dev/null 2>&1
  git -C "$worktree" config user.name "Resident"
  git -C "$worktree" config user.email "resident@example.com"
  printf 'stub\n' >"$worktree/README.md"
  git -C "$worktree" add README.md
  git -C "$worktree" commit -m "init" >/dev/null 2>&1
fi
printf 'new:%s\n' "$issue_id" >>"$capture_dir/worktree-ops.log"
printf 'WORKTREE=%s\n' "$worktree"
printf 'BRANCH=agent/demo/issue-%s-fresh\n' "$issue_id"
EOF
chmod +x "$bin_dir/new-worktree.sh"

cat >"$bin_dir/reuse-issue-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worktree="${1:?worktree required}"
issue_id="${2:?issue id required}"
printf 'reuse-fail:%s:%s\n' "$issue_id" "$worktree" >>"${TEST_CAPTURE_DIR:?}/worktree-ops.log"
echo "invalid managed worktree: ${worktree}" >&2
exit 1
EOF
chmod +x "$bin_dir/reuse-issue-worktree.sh"

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
session="${1:?session required}"
worktree="${2:?worktree required}"
prompt_file="${3:?prompt file required}"
capture_dir="${TEST_CAPTURE_DIR:?}"
task_count="${ACP_RESIDENT_TASK_COUNT:-0}"
printf 'SESSION=%s\n' "$session" >"$capture_dir/runner-${task_count}.env"
printf 'WORKTREE=%s\n' "$worktree" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_WORKER_ENABLED=%s\n' "${ACP_RESIDENT_WORKER_ENABLED:-}" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_WORKER_KEY=%s\n' "${ACP_RESIDENT_WORKER_KEY:-}" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_LANE_KIND=%s\n' "${ACP_RESIDENT_LANE_KIND:-}" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_LANE_VALUE=%s\n' "${ACP_RESIDENT_LANE_VALUE:-}" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_TASK_COUNT=%s\n' "${ACP_RESIDENT_TASK_COUNT:-}" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_WORKTREE_REUSED=%s\n' "${ACP_RESIDENT_WORKTREE_REUSED:-}" >>"$capture_dir/runner-${task_count}.env"
printf 'ACP_RESIDENT_OPENCLAW_SESSION_ID=%s\n' "${ACP_RESIDENT_OPENCLAW_SESSION_ID:-}" >>"$capture_dir/runner-${task_count}.env"
cp "$prompt_file" "$capture_dir/prompt-${task_count}.md"
exit 0
EOF
chmod +x "$bin_dir/run-codex-safe.sh"

run_issue() {
  local issue_id="${1:?issue id required}"
  PATH="$shim_dir:$PATH" \
  ACP_PROJECT_ID="demo" \
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  TEST_CAPTURE_DIR="$capture_dir" \
  bash "$bin_dir/start-issue-worker.sh" "$issue_id" >/dev/null 2>"$capture_dir/stderr-${issue_id}.log"
}

run_issue 440
run_issue 441

lane_key="issue-lane-recurring-general-openclaw-safe"
metadata_file="$agent_root/state/resident-workers/issues/$lane_key/metadata.env"
resident_alias_path="$agent_root/state/resident-workers/issues/$lane_key/worktree"

test -f "$metadata_file"
grep -q '^new:440$' "$capture_dir/worktree-ops.log"
grep -q "^reuse-fail:441:$resident_alias_path$" "$capture_dir/worktree-ops.log"
grep -q '^new:441$' "$capture_dir/worktree-ops.log"
grep -q '^RESIDENT_REUSE_FALLBACK=issue-441 reason=invalid managed worktree:' "$capture_dir/stderr-441.log"
grep -q '^SESSION=demo-issue-441$' "$capture_dir/runner-1.env"
grep -q "^WORKTREE=$resident_alias_path$" "$capture_dir/runner-1.env"
grep -q '^ACP_RESIDENT_TASK_COUNT=1$' "$capture_dir/runner-1.env"
grep -q '^ACP_RESIDENT_WORKTREE_REUSED=no$' "$capture_dir/runner-1.env"
grep -q '^ACP_RESIDENT_OPENCLAW_SESSION_ID=demo-resident-session-issue-441$' "$capture_dir/runner-1.env"
grep -q '^ISSUE_ID=441$' "$metadata_file"
grep -q "^WORKTREE=$resident_alias_path$" "$metadata_file"
metadata_worktree_realpath="$(awk -F= '/^WORKTREE_REALPATH=/{print $2; exit}' "$metadata_file")"
test -n "$metadata_worktree_realpath"
test "$(cd "$metadata_worktree_realpath" && pwd -P)" = "$(cd "$capture_dir/worktree-441" && pwd -P)"
grep -q '^TASK_COUNT=1$' "$metadata_file"
grep -q '^LAST_RUN_SESSION=demo-issue-441$' "$metadata_file"
grep -q '^LAST_WORKTREE_REUSED=no$' "$metadata_file"

echo "start issue worker resident reuse fallback test passed"
