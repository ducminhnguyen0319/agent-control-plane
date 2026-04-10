#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

node_bin_dir="$(dirname "$(command -v node)")"
bin_dir="$tmpdir/bin"
tools_dir="$tmpdir/tools/bin"
labels_log="$tmpdir/labels.log"

mkdir -p "$bin_dir" "$tools_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  printf '5000\n'
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"body":"No recurring schedule here.","labels":[{"name":"agent-running"},{"name":"agent-schedule-10m"}]}
JSON
  exit 0
fi

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

cat >"$tools_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_LABELS_LOG:?}"
EOF

chmod +x "$bin_dir/gh" "$tools_dir/agent-github-update-labels"

export PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_LABELS_LOG="$labels_log"
export F_LOSNING_REPO_SLUG="example/repo"

# shellcheck source=/dev/null
export FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes"
source "$HOOKS_FILE"
FLOW_TOOLS_DIR="$tools_dir"
REPO_SLUG="example/repo"

heartbeat_sync_issue_labels 123

grep -q -- '--repo-slug example/repo --number 123' "$labels_log"
grep -q -- '--remove agent-schedule-10m' "$labels_log"
grep -q -- '--remove agent-running' "$labels_log"
grep -q -- '--remove agent-blocked' "$labels_log"
grep -q -- '--remove agent-scheduled' "$labels_log"
if grep -q -- '--add agent-scheduled' "$labels_log"; then
  echo "unexpected scheduled add args in label update command" >&2
  exit 1
fi

echo "heartbeat sync issue labels empty-schedule test passed"
