#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENCODE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-opencode-session"
KILO_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-kilo-session"

help_output="$(bash "$OPENCODE_SCRIPT" --help)"
grep -q 'Placeholder adapter for the roadmap' <<<"$help_output"
grep -q '`opencode`' <<<"$help_output"

help_output="$(bash "$KILO_SCRIPT" --help)"
grep -q 'Placeholder adapter for the roadmap' <<<"$help_output"
grep -q '`kilo`' <<<"$help_output"

set +e
opencode_output="$(bash "$OPENCODE_SCRIPT" --session demo 2>&1)"
opencode_status=$?
kilo_output="$(bash "$KILO_SCRIPT" --session demo 2>&1)"
kilo_status=$?
set -e

if [[ "$opencode_status" -eq 0 ]]; then
  echo "expected opencode placeholder adapter to fail" >&2
  exit 1
fi

if [[ "$kilo_status" -eq 0 ]]; then
  echo "expected kilo placeholder adapter to fail" >&2
  exit 1
fi

grep -q 'execution is not implemented yet' <<<"$opencode_output"
grep -q 'Choose codex, claude, or openclaw for live runs today.' <<<"$opencode_output"
grep -q 'execution is not implemented yet' <<<"$kilo_output"
grep -q 'Choose codex, claude, or openclaw for live runs today.' <<<"$kilo_output"

echo "placeholder worker adapters test passed"
