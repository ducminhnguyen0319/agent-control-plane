#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/bin/sync-pr-labels.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

adapter_bin_dir="$tmpdir/bin"
tools_bin_dir="$tmpdir/tools/bin"
shim_bin_dir="$tmpdir/shims"
calls_log="$tmpdir/label-calls.log"

mkdir -p "$adapter_bin_dir" "$tools_bin_dir" "$shim_bin_dir"
cp "$SOURCE_SCRIPT" "$adapter_bin_dir/sync-pr-labels.sh"
cp "$FLOW_CONFIG_LIB" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$tools_bin_dir/flow-shell-lib.sh"

cat >"$adapter_bin_dir/pr-risk.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"isManagedByAgent":true,"agentLane":"fix","linkedIssueId":null,"isBlocked":false,"hasManualFixOverride":false,"eligibleForAutoMerge":false,"riskTier":"high","checksBypassed":false}
JSON
EOF

cat >"$tools_bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_LABEL_CALLS_LOG:?}"
EOF

cat >"$shim_bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  label)
    exit 0
    ;;
esac
echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x \
  "$adapter_bin_dir/pr-risk.sh" \
  "$adapter_bin_dir/sync-pr-labels.sh" \
  "$tools_bin_dir/flow-config-lib.sh" \
  "$tools_bin_dir/flow-shell-lib.sh" \
  "$tools_bin_dir/agent-github-update-labels" \
  "$shim_bin_dir/gh"

TEST_LABEL_CALLS_LOG="$calls_log" \
PATH="$shim_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
bash "$adapter_bin_dir/sync-pr-labels.sh" 601 >/dev/null

grep -q -- '--add agent-repair-queued' "$calls_log"
if grep -q -- '--add agent-fix-needed' "$calls_log"; then
  echo "sync-pr-labels unexpectedly re-added the manual override label for fix lane" >&2
  cat "$calls_log" >&2
  exit 1
fi

echo "sync-pr-labels fix lane uses repair queued test passed"
