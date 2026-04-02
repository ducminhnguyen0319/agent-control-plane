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

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  echo 'GraphQL: API rate limit already exceeded for user ID 123.' >&2
  exit 1
fi

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  if [[ "$route" == user/repos\?* ]]; then
    printf '[[{"id":123,"full_name":"example/demo"}]]\n'
    exit 0
  fi
  if [[ "$route" == "repositories/123/pulls?state=open&per_page=20" ]]; then
    printf '{"message":"Service unavailable"}\n'
    exit 1
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
flow_github_pr_list_json "example/demo" open 20
EOF
)"

test "$output" = "[]"

echo "flow github pr list returns empty on rest api error test passed"
