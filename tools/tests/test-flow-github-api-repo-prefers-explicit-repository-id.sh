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

if [[ "${1:-}" != "api" ]]; then
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi

route="${2:-}"
shift 2 || true

case "$route" in
  repos/example/repo/issues/42)
    exit 1
    ;;
  repositories/123/issues/42)
    printf '{"number":42,"state":"open"}\n'
    exit 0
    ;;
  user/repos*)
    echo "unexpected repo discovery route: $route" >&2
    exit 98
    ;;
  *)
    echo "unexpected gh api route: $route" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$bin_dir/flow-config-lib.sh" "$bin_dir/flow-shell-lib.sh" "$bin_dir/gh"

output="$(
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_REPO_ID="123" \
  ACP_REPO_SLUG="example/repo" \
  bash -c 'source "'"$bin_dir"'/flow-config-lib.sh"; flow_github_api_repo "example/repo" "issues/42"'
)"

test "$(jq -r '.number' <<<"$output")" = "42"
test "$(jq -r '.state' <<<"$output")" = "open"

echo "flow github api repo prefers explicit repository id test passed"
