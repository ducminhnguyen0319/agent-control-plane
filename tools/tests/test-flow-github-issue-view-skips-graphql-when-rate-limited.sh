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

if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  if [[ "${3:-}" == "--jq" ]]; then
    printf '0\n'
  else
    printf '{"resources":{"graphql":{"remaining":0}}}\n'
  fi
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  echo "unexpected gh issue view invocation: $*" >&2
  exit 1
fi

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  if [[ "$route" == "repos/example/demo/issues/7" ]]; then
    cat <<'JSON'
{"number":7,"state":"open","title":"Issue title","body":"Issue body","html_url":"https://github.com/example/demo/issues/7","labels":[{"name":"agent-keep-open"}],"created_at":"2026-04-02T10:00:00Z","updated_at":"2026-04-02T10:01:00Z"}
JSON
    exit 0
  fi
  if [[ "$route" == "repos/example/demo/issues/7/comments?per_page=100" ]]; then
    printf '[]\n'
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
flow_github_issue_view_json "example/demo" 7
EOF
)"

test "$(jq -r '.number' <<<"$output")" = "7"
test "$(jq -r '.title' <<<"$output")" = "Issue title"
test "$(jq -r '.labels[0].name' <<<"$output")" = "agent-keep-open"
test "$(jq '.comments | length' <<<"$output")" -eq 0

echo "flow github issue view skips graphql when rate limited test passed"
