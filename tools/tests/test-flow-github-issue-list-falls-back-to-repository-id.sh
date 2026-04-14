#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  echo 'GraphQL: Could not resolve to a Repository with the name "example/demo".' >&2
  exit 1
fi

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  if [[ "$route" == "repos/example/demo/issues?state=open&per_page=100" ]]; then
    echo '{"message":"Not Found"}' >&2
    exit 1
  fi
  if [[ "$route" == user/repos\?* ]]; then
    printf '[[{"id":123,"full_name":"example/demo"}]]\n'
    exit 0
  fi
  if [[ "$route" == "repositories/123/issues?state=open&per_page=100" ]]; then
    cat <<'JSON'
[[{"number":2,"created_at":"2026-03-27T10:00:00Z","updated_at":"2026-03-27T10:05:00Z","title":"Ready issue","html_url":"https://github.com/example/demo/issues/2","labels":[{"name":"agent-keep-open"}]},{"number":9,"created_at":"2026-03-27T10:01:00Z","updated_at":"2026-03-27T10:06:00Z","title":"PR mirror","html_url":"https://github.com/example/demo/pull/9","labels":[],"pull_request":{"url":"https://api.github.com/repos/example/demo/pulls/9"}}]]
JSON
    exit 0
  fi
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh"

output="$(
  LIB_PATH="$bin_dir/flow-config-lib.sh" \
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"
flow_github_issue_list_json "example/demo" open 100
EOF
)"

test "$(jq 'length' <<<"$output")" -eq 1
test "$(jq -r '.[0].number' <<<"$output")" = "2"
test "$(jq -r '.[0].labels[0].name' <<<"$output")" = "agent-keep-open"
test "$(jq -r '.[0].createdAt' <<<"$output")" = "2026-03-27T10:00:00Z"

echo "flow github issue list falls back to repository id test passed"
