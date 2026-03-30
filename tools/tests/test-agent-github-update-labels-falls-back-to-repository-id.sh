#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/agent-github-update-labels"
CONFIG_LIB_SRC="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
SHELL_LIB_SRC="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
payload_file="$tmpdir/payload.json"
mkdir -p "$bin_dir"

cp "$SCRIPT_SRC" "$bin_dir/agent-github-update-labels"
cp "$CONFIG_LIB_SRC" "$bin_dir/flow-config-lib.sh"
cp "$SHELL_LIB_SRC" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  if [[ "$route" == "repos/example/demo/issues/42" ]]; then
    echo '{"message":"Not Found"}' >&2
    exit 1
  fi
  if [[ "$route" == user/repos\?* ]]; then
    printf '[[{"id":123,"full_name":"example/demo"}]]\n'
    exit 0
  fi
  if [[ "$route" == "repositories/123/issues/42" ]]; then
    if [[ " $* " == *" --method PATCH "* ]]; then
      cat >"${TEST_PAYLOAD_FILE:?}"
      exit 0
    fi
    printf '{"labels":[{"name":"agent-blocked"}]}\n'
    exit 0
  fi
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh" "$bin_dir/agent-github-update-labels"

TEST_PAYLOAD_FILE="$payload_file" \
PATH="$bin_dir:$PATH" \
bash "$bin_dir/agent-github-update-labels" --repo-slug example/demo --number 42 --add agent-running --remove agent-blocked

test "$(jq -r '.labels[0]' "$payload_file")" = "agent-running"
test "$(jq '.labels | length' "$payload_file")" -eq 1

echo "agent github update labels falls back to repository id test passed"
