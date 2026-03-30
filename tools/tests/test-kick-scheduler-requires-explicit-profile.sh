#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KICK_SCRIPT="${FLOW_ROOT}/tools/bin/kick-scheduler.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"
profile_home="$tmpdir/profiles"
mkdir -p "$bin_dir" "$profile_home/alpha" "$profile_home/beta" "$assets_dir"

cp "$KICK_SCRIPT" "$bin_dir/kick-scheduler.sh"
cp "$FLOW_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
printf '{}
' >"$assets_dir/workflow-catalog.json"

cat >"$profile_home/alpha/control-plane.yaml" <<'EOF'
schema_version: "1"
id: "alpha"
repo:
  slug: "example/alpha"
EOF

cat >"$profile_home/beta/control-plane.yaml" <<'EOF'
schema_version: "1"
id: "beta"
repo:
  slug: "example/beta"
EOF

set +e
output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$bin_dir/kick-scheduler.sh" 1 2>&1)"
status=$?
set -e

test "$status" -eq 64
grep -q '^explicit profile selection required for kick-scheduler.sh when multiple available profiles exist\.$' <<<"$output"
grep -q '^Set ACP_PROJECT_ID=<id> or AGENT_PROJECT_ID=<id> when multiple available profiles exist\.$' <<<"$output"

echo "kick scheduler explicit profile guard test passed"
