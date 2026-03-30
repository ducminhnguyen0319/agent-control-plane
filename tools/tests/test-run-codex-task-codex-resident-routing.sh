#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/run-codex-task.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace_root="$tmpdir/workspace/tools"
bin_dir="$workspace_root/bin"
shared_home="$tmpdir/shared-home"
flow_root="$shared_home/skills/openclaw/agent-control-plane"
flow_bin_dir="$flow_root/tools/bin"
flow_assets_dir="$flow_root/assets"
profile_home="$tmpdir/profiles"
repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
session="acp-issue-778"
prompt_file="$tmpdir/prompt.md"
capture_file="$tmpdir/capture.log"

mkdir -p "$bin_dir" "$flow_bin_dir" "$flow_assets_dir" "$profile_home/demo" "$repo_root" "$worktree_root"
printf 'skill root\n' >"$flow_root/SKILL.md"
printf '{}\n' >"$flow_assets_dir/workflow-catalog.json"
cp "$SOURCE_SCRIPT" "$bin_dir/run-codex-task.sh"
cp "$FLOW_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$profile_home/demo/control-plane.yaml" <<'EOF'
id: "demo"
session_naming:
  issue_prefix: "acp-issue-"
  pr_prefix: "acp-pr-"
execution:
  coding_worker: "codex"
EOF

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test"
git -C "$repo_root" config user.email "test@example.com"
printf 'seed\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1
worktree="$worktree_root/issue-778"
git -C "$repo_root" worktree add -b agent/demo/issue-778 "$worktree" >/dev/null 2>&1

cat >"$flow_bin_dir/agent-project-run-openclaw-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'RUNNER=openclaw\n' >"${TEST_CAPTURE_FILE:?}"
printf '%s\n' "$@" >>"${TEST_CAPTURE_FILE:?}"
EOF

cat >"$flow_bin_dir/agent-project-run-codex-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'RUNNER=codex\n' >"${TEST_CAPTURE_FILE:?}"
printf '%s\n' "$@" >>"${TEST_CAPTURE_FILE:?}"
EOF

chmod +x \
  "$bin_dir/run-codex-task.sh" \
  "$bin_dir/flow-config-lib.sh" \
  "$bin_dir/flow-shell-lib.sh" \
  "$flow_bin_dir/agent-project-run-openclaw-session" \
  "$flow_bin_dir/agent-project-run-codex-session"

printf 'Prompt\n' >"$prompt_file"

TEST_CAPTURE_FILE="$capture_file" \
SHARED_AGENT_HOME="$tmpdir/shared-home" \
ACP_ROOT="$flow_root" \
ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
ACP_PROJECT_ID="demo" \
ACP_CODING_WORKER="codex" \
ACP_CODEX_PROFILE_SAFE="demo_safe" \
ACP_CODEX_PROFILE_BYPASS="demo_bypass" \
ACP_AGENT_ROOT="$tmpdir/agent-root" \
ACP_RUNS_ROOT="$tmpdir/agent-root/runs" \
ACP_AGENT_REPO_ROOT="$repo_root" \
ACP_REPO_ROOT="$repo_root" \
ACP_WORKTREE_ROOT="$worktree_root" \
ACP_RETAINED_REPO_ROOT="$tmpdir/retained" \
ACP_ISSUE_ID="778" \
ACP_RESIDENT_WORKER_ENABLED="yes" \
ACP_RESIDENT_WORKER_KEY="issue-lane-recurring-general-codex-safe" \
ACP_RESIDENT_WORKER_DIR="$tmpdir/agent-root/state/resident-workers/issues/issue-lane-recurring-general-codex-safe" \
ACP_RESIDENT_WORKER_META_FILE="$tmpdir/agent-root/state/resident-workers/issues/issue-lane-recurring-general-codex-safe/metadata.env" \
ACP_RESIDENT_TASK_COUNT="3" \
ACP_RESIDENT_WORKTREE_REUSED="yes" \
bash "$bin_dir/run-codex-task.sh" safe "$session" "$worktree" "$prompt_file"

grep -q '^RUNNER=codex$' "$capture_file"
grep -q -- '--safe-profile' "$capture_file"
grep -q -- 'demo_safe' "$capture_file"
grep -q -- '--context' "$capture_file"
grep -q -- 'CODING_WORKER=codex' "$capture_file"
grep -q -- 'RESIDENT_WORKER_ENABLED=yes' "$capture_file"
grep -q -- 'RESIDENT_TASK_COUNT=3' "$capture_file"
if grep -q -- '--keep-agent' "$capture_file"; then
  echo "codex resident routing should not pass openclaw keep-agent flags" >&2
  exit 1
fi

echo "run-codex-task codex resident routing test passed"
