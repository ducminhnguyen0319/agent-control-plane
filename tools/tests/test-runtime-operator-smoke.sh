#!/usr/bin/env bash
# Smoke test for runtime operator behavior
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"

echo "=== Runtime Operator Smoke Test ==="

# Test 1: Check flow-config-lib.sh exists and is valid
echo "Test 1: flow-config-lib.sh syntax"
if [[ ! -f "${SCRIPT_DIR}/flow-config-lib.sh" ]]; then
  echo "FAIL: flow-config-lib.sh not found"
  exit 1
fi
bash -n "${SCRIPT_DIR}/flow-config-lib.sh" || { echo "FAIL: syntax error"; exit 1; }
echo "PASS"

# Test 2: Check kick-scheduler-wrapper.sh exists and is valid
echo "Test 2: kick-scheduler-wrapper.sh syntax"
if [[ ! -f "${SCRIPT_DIR}/kick-scheduler-wrapper.sh" ]]; then
  echo "FAIL: kick-scheduler-wrapper.sh not found"
  exit 1
fi
bash -n "${SCRIPT_DIR}/kick-scheduler-wrapper.sh" || { echo "FAIL: syntax error"; exit 1; }
echo "PASS"

# Test 3: Check doctor script exists
echo "Test 3: flow-runtime-doctor.sh exists"
if [[ ! -f "${SCRIPT_DIR}/flow-runtime-doctor.sh" ]]; then
  echo "FAIL: flow-runtime-doctor.sh not found"
  exit 1
fi
bash -n "${SCRIPT_DIR}/flow-runtime-doctor.sh" || { echo "FAIL: syntax error"; exit 1; }
echo "PASS"

echo "=== All runtime operator smoke tests PASSED ==="
