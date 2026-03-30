#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/provider-cooldown-state.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_root="$tmpdir/state"
config_file="$tmpdir/control-plane.yaml"

cat >"$config_file" <<EOF
id: "quota-demo"
runtime:
  orchestrator_agent_root: "${tmpdir}/agent"
  state_root: "${state_root}"
execution:
  coding_worker: "openclaw"
  provider_quota:
    cooldowns: "5,10"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

get_output="$(
  AGENT_CONTROL_PLANE_CONFIG="$config_file" \
  CODING_WORKER="claude" \
  CLAUDE_MODEL="fallback-sonnet" \
  bash "$SCRIPT" get
)"

grep -q '^BACKEND=claude$' <<<"$get_output"
grep -q '^MODEL=fallback-sonnet$' <<<"$get_output"
grep -q '^PROVIDER_KEY=claude-fallback-sonnet$' <<<"$get_output"

echo "provider cooldown state runtime worker context test passed"
