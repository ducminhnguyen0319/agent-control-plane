#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
tools_dir="$tmpdir/tools/bin"
profile_registry_root="$tmpdir/profile-registry"
profile_dir="$profile_registry_root/alpha"
agent_root="$tmpdir/agent-root"
repo_root="$tmpdir/repo-root"

mkdir -p "$bin_dir" "$tools_dir" "$profile_dir" "$agent_root" "$repo_root"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "alpha"
repo:
  slug: "example/repo"
  root: "$repo_root"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$agent_root"
  worktree_root: "$agent_root/worktrees"
  agent_repo_root: "$repo_root"
  runs_root: "$agent_root/runs"
  history_root: "$agent_root/history"
  state_root: "$agent_root/state"
  retained_repo_root: "$repo_root"
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh should not be called in this test" >&2
exit 1
EOF

cat >"$tools_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh: API rate limit exceeded (HTTP 403)" >&2
exit 1
EOF

chmod +x "$bin_dir/gh" "$tools_dir/agent-github-update-labels"

export PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export ACP_PROJECT_ID="alpha"
export ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root"

# shellcheck source=/dev/null
source "$HOOKS_FILE"
FLOW_TOOLS_DIR="$tools_dir"
REPO_SLUG="example/repo"

heartbeat_mark_issue_running 123 no
heartbeat_mark_issue_running 124 yes

echo "heartbeat mark issue running tolerates label rate limit test passed"
