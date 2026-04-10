#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

node_bin_dir="$(dirname "$(command -v node)")"
bin_dir="$tmpdir/bin"
tools_dir="$tmpdir/tools/bin"

mkdir -p "$bin_dir" "$tools_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  printf '[]\n'
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  cat <<'JSON'
[
  {"number":615,"createdAt":"2026-04-02T02:00:00Z","labels":[]}
]
JSON
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

cat >"$tools_dir/retry-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'OUT'
KIND=issue
ITEM_ID=0
ATTEMPTS=0
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=
READY=yes
LAST_REASON=
UPDATED_AT=
OUT
EOF

chmod +x "$bin_dir/gh" "$tools_dir/retry-state.sh"

export PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export F_LOSNING_REPO_SLUG="example/repo"
export ACP_MANAGED_PR_BRANCH_GLOBS="agent/example/* codex/* openclaw/*"
export FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes"

# shellcheck source=/dev/null
source "$HOOKS_FILE"
FLOW_TOOLS_DIR="$tools_dir"
REPO_SLUG="example/repo"

open_agent_pr_issue_ids="$(heartbeat_open_agent_pr_issue_ids)"
ready_issue_ids="$(heartbeat_list_ready_issue_ids)"

[[ "$open_agent_pr_issue_ids" == "[]" ]]
grep -q '^615$' <<<"$ready_issue_ids"

echo "heartbeat empty open PR json test passed"
