#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
metadata_file="$tmpdir/metadata.env"

mkdir -p "$bin_dir" "$worktree/.git"
cp "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"
cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$metadata_file" <<EOF
ISSUE_ID=1
WORKTREE=$worktree
TASK_COUNT=1
LAST_STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

TEST_RESULT="$(
  LIB_PATH="$bin_dir/flow-resident-worker-lib.sh" \
  METADATA_FILE="$metadata_file" \
  bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"
ISSUE_ID="2"
WORKTREE="/tmp/current-worktree"
TASK_COUNT="9"
if flow_resident_issue_can_reuse "$METADATA_FILE" 12 86400; then
  :
else
  exit 1
fi
printf 'ISSUE_ID=%s\n' "$ISSUE_ID"
printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'TASK_COUNT=%s\n' "$TASK_COUNT"
EOF
)"

grep -q '^ISSUE_ID=2$' <<<"$TEST_RESULT"
grep -q '^WORKTREE=/tmp/current-worktree$' <<<"$TEST_RESULT"
grep -q '^TASK_COUNT=9$' <<<"$TEST_RESULT"

echo "flow resident can reuse does not leak metadata test passed"
