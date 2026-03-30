#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/provider-cooldown-state.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_root="$tmpdir/state"
config_file="$tmpdir/control-plane.yaml"
model="openrouter/stepfun/step-3.5-flash:free"

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
    model: "${model}"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

get_output="$(
  AGENT_CONTROL_PLANE_CONFIG="$config_file" \
  bash "$SCRIPT" get
)"

grep -q '^BACKEND=openclaw$' <<<"$get_output"
grep -q "^MODEL=${model}$" <<<"$get_output"
grep -q '^ATTEMPTS=0$' <<<"$get_output"
grep -q '^READY=yes$' <<<"$get_output"

schedule_output="$(
  AGENT_CONTROL_PLANE_CONFIG="$config_file" \
  bash "$SCRIPT" schedule provider-quota-limit
)"

grep -q '^PROVIDER_KEY=openclaw-openrouter-stepfun-step-3.5-flash-free$' <<<"$schedule_output"
grep -q '^ATTEMPTS=1$' <<<"$schedule_output"
grep -q '^READY=no$' <<<"$schedule_output"
grep -q '^LAST_REASON=provider-quota-limit$' <<<"$schedule_output"
test -f "$state_root/retries/providers/openclaw-openrouter-stepfun-step-3.5-flash-free.env"

clear_output="$(
  AGENT_CONTROL_PLANE_CONFIG="$config_file" \
  bash "$SCRIPT" clear
)"

grep -q '^ATTEMPTS=0$' <<<"$clear_output"
grep -q '^READY=yes$' <<<"$clear_output"
test ! -f "$state_root/retries/providers/openclaw-openrouter-stepfun-step-3.5-flash-free.env"

echo "provider cooldown state test passed"
