#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_FILE="${FLOW_ROOT}/hooks/issue-reconcile-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

stub_tools="$tmpdir/tools/bin"
capture_file="$tmpdir/labels.log"
mkdir -p "$stub_tools"

cat >"$stub_tools/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_CAPTURE_FILE:?}"
EOF
chmod +x "$stub_tools/agent-github-update-labels"

export ISSUE_ID=42
export TEST_CAPTURE_FILE="$capture_file"

# shellcheck source=/dev/null
source "$HOOK_FILE"

FLOW_TOOLS_DIR="$stub_tools"
REPO_SLUG="example/repo"

issue_remove_running

grep -q -- '--remove agent-running' "$capture_file"
grep -q -- '--remove agent-blocked' "$capture_file"

echo "issue reconcile hooks success clears blocked label test passed"
