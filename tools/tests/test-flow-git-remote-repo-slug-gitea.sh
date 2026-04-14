#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_PATH="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

git -C "$tmpdir" init -q

LIB_PATH="$LIB_PATH" \
tmpdir="$tmpdir" \
bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"

git -C "$tmpdir" remote add origin http://127.0.0.1:3300/acp-admin/acp-sandbox.git
test "$(flow_git_remote_repo_slug "$tmpdir")" = "acp-admin/acp-sandbox"

git -C "$tmpdir" remote set-url origin git@127.0.0.1:acp-admin/acp-sandbox.git
test "$(flow_git_remote_repo_slug "$tmpdir")" = "acp-admin/acp-sandbox"

git -C "$tmpdir" remote set-url origin ssh://git@127.0.0.1/acp-admin/acp-sandbox.git
test "$(flow_git_remote_repo_slug "$tmpdir")" = "acp-admin/acp-sandbox"
EOF

echo "flow git remote repo slug gitea test passed"
