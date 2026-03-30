#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
FLOW_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
profile_home="$tmpdir/profiles"
mkdir -p "$bin_dir" "$assets_dir" "$profile_home/alpha" "$profile_home/beta"

cp "$FLOW_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
cp "$FLOW_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

for script in   heartbeat-safe-auto.sh   start-issue-worker.sh   start-pr-fix-worker.sh   start-pr-review-worker.sh   new-worktree.sh   new-pr-worktree.sh   worker-status.sh; do
  cp "$FLOW_ROOT/tools/bin/${script}" "$bin_dir/${script}"
done

cat >"$profile_home/alpha/control-plane.yaml" <<'EOF'
schema_version: "1"
id: "alpha"
repo:
  slug: "example/alpha"
EOF

cat >"$profile_home/beta/control-plane.yaml" <<'EOF'
schema_version: "1"
id: "beta"
repo:
  slug: "example/beta"
EOF

check_guard() {
  local script="${1:?script required}"
  shift || true

  set +e
  local output
  output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$bin_dir/$script" "$@" 2>&1)"
  local status=$?
  set -e

  test "$status" -eq 64
  grep -q "^explicit profile selection required for ${script} when multiple available profiles exist\.$" <<<"$output"
  grep -q '^Set ACP_PROJECT_ID=<id> or AGENT_PROJECT_ID=<id> when multiple available profiles exist\.$' <<<"$output"
}

check_guard heartbeat-safe-auto.sh
check_guard start-issue-worker.sh 101
check_guard start-pr-fix-worker.sh 601
check_guard start-pr-review-worker.sh 601
check_guard new-worktree.sh 101
check_guard new-pr-worktree.sh 601 feature/test
check_guard worker-status.sh demo-session

echo "manual operator explicit profile guard test passed"
