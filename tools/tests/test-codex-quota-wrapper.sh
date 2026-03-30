#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="${FLOW_ROOT}/tools/bin/codex-quota"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
log_file="$tmpdir/node-args.log"
expected_entry="${FLOW_ROOT}/tools/vendor/codex-quota/codex-quota.js"

mkdir -p "$bin_dir"

cat >"$bin_dir/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${LOG_FILE:?}"
EOF

chmod +x "$bin_dir/node"

LOG_FILE="$log_file" \
ACP_CODEX_QUOTA_NODE_BIN="$bin_dir/node" \
bash "$WRAPPER" codex list --json

actual_entry="$(
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$(sed -n '1p' "$log_file")"
)"

test "$actual_entry" = "$expected_entry"
test "$(sed -n '2p' "$log_file")" = "codex"
test "$(sed -n '3p' "$log_file")" = "list"
test "$(sed -n '4p' "$log_file")" = "--json"

echo "codex quota wrapper test passed"
