#!/usr/bin/env bash
# test-adapters.sh
# Test all ACP backend adapters for production-readiness
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

passed() {
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

failed() {
  echo "FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warned() {
  echo "WARN: $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

test_adapter() {
  local adapter_script="$1"
  local adapter_name="$(basename "$adapter_script" .sh)"
  
  echo "=== Testing $adapter_name ==="
  
  # Source the adapter
  if ! source "$adapter_script" 2>/dev/null; then
    failed "Cannot source $adapter_script"
    return 1
  fi
  
  # Test adapter_info
  echo "--- adapter_info() ---"
  if info_output="$(adapter_info 2>&1)"; then
    passed "$adapter_name adapter_info() works"
    echo "$info_output" | while IFS= read -r line; do
      echo "  $line"
    done
  else
    failed "$adapter_name adapter_info() failed"
  fi
  
  # Test adapter_health_check
  echo "--- adapter_health_check() ---"
  if health_output="$(adapter_health_check 2>&1)"; then
    passed "$adapter_name adapter_health_check() passed"
    echo "$health_output" | while IFS= read -r line; do
      echo "  $line"
      if [[ "$line" == WARN:* ]]; then
        WARN_COUNT=$((WARN_COUNT + 1))
      fi
    done
  else
    failed "$adapter_name adapter_health_check() failed: $health_output"
  fi
  
  echo ""
}

echo "ACP Adapter Production-Readiness Tests"
echo "================================"
echo ""

# Test all adapters
for adapter in "$SCRIPT_DIR"/../bin/*-adapter.sh; do
  if [[ -f "$adapter" ]]; then
    test_adapter "$adapter"
  fi
done

echo "================================"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $WARN_COUNT warnings"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi

exit 0
