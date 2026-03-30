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

captured_payload_file="$tmpdir/captured-payload.json"
cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "api" ]]; then
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi

route="${2:-}"
shift 2 || true

input_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_file="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$route" in
  repos/example/repo/issues/42)
    if [[ -n "$input_file" && -f "$input_file" ]]; then
      cat "$input_file" >/dev/null
    fi
    exit 1
    ;;
  repositories/123/issues/42)
    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
      echo "missing preserved input file" >&2
      exit 97
    fi
    cp "$input_file" "${TEST_CAPTURED_PAYLOAD_FILE:?}"
    printf '{"number":42,"state":"open"}\n'
    exit 0
    ;;
  *)
    echo "unexpected gh api route: $route" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$bin_dir/flow-config-lib.sh" "$bin_dir/flow-shell-lib.sh" "$bin_dir/gh"

output="$(
  LIB_PATH="$bin_dir/flow-config-lib.sh" \
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_REPO_ID="123" \
  ACP_REPO_SLUG="example/repo" \
  TEST_CAPTURED_PAYLOAD_FILE="$captured_payload_file" \
  bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"
printf '{"body":"patched body"}' | flow_github_api_repo "example/repo" "issues/42" --method PATCH --input -
EOF
)"

test "$(jq -r '.number' <<<"$output")" = "42"
test "$(jq -r '.state' <<<"$output")" = "open"
test "$(jq -r '.body' "$captured_payload_file")" = "patched body"

echo "flow github api repo fallback preserves input test passed"
