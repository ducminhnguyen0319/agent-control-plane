#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENCODE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-opencode-session"
KILO_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-kilo-session"

# Both adapters should accept --help and describe their backend
help_output="$(bash "$OPENCODE_SCRIPT" --help)"
grep -q 'Crush' <<<"$help_output"
grep -q 'opencode' <<<"$help_output"
grep -q '\-\-opencode-model' <<<"$help_output"

help_output="$(bash "$KILO_SCRIPT" --help)"
grep -q 'Kilo' <<<"$help_output"
grep -q '\-\-kilo-model' <<<"$help_output"

# Both adapters should fail gracefully when required args are missing
set +e
opencode_output="$(bash "$OPENCODE_SCRIPT" 2>&1)"
opencode_status=$?
kilo_output="$(bash "$KILO_SCRIPT" 2>&1)"
kilo_status=$?
set -e

if [[ "$opencode_status" -eq 0 ]]; then
  echo "expected opencode adapter to fail without required args" >&2
  exit 1
fi

if [[ "$kilo_status" -eq 0 ]]; then
  echo "expected kilo adapter to fail without required args" >&2
  exit 1
fi

echo "worker adapter help and validation test passed"
