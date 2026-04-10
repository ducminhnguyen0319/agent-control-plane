#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

node_bin_dir="$(dirname "$(command -v node)")"
bin_dir="$tmpdir/bin"
tools_dir="$tmpdir/tools/bin"
gh_log="$tmpdir/gh.log"

mkdir -p "$bin_dir" "$tools_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  printf '%s\n' "$*" >>"${TEST_GH_LOG:?}"
  cat <<'JSON'
{"number":615,"body":"Schedule: every 1h","labels":[{"name":"agent-keep-open"},{"name":"agent-exclusive"}],"comments":[]}
JSON
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

export PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_GH_LOG="$gh_log"
export F_LOSNING_REPO_SLUG="example/repo"
export FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes"

# shellcheck source=/dev/null
source "$HOOKS_FILE"
REPO_SLUG="example/repo"

[[ "$(heartbeat_issue_is_recurring 615)" == "yes" ]]
[[ "$(heartbeat_issue_is_scheduled 615)" == "yes" ]]
[[ "$(heartbeat_issue_is_exclusive 615)" == "yes" ]]

if [[ "$(wc -l <"$gh_log" | tr -d '[:space:]')" != "1" ]]; then
  echo "heartbeat issue view cache did not reuse the first issue payload" >&2
  exit 1
fi

echo "heartbeat hooks issue view cache test passed"
