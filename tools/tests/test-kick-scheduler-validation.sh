#!/usr/bin/env bash
set -euo pipefail

# Simple test for kick-scheduler.sh validation
echo "Testing kick-scheduler.sh validation..."

# Test 1: REPO_SLUG not configured
output="$(REPO_SLUG="" bash tools/bin/kick-scheduler.sh 2>&1 || true)"
if echo "$output" | grep -q "KICK_STATUS=repo-not-configured"; then
  echo "TEST 1 PASSED: repo-not-configured detected"
else
  echo "TEST 1 FAILED"
  exit 1
fi

# Test 2: Invalid format
output="$(REPO_SLUG="invalid-format" bash tools/bin/kick-scheduler.sh 2>&1 || true)"
if echo "$output" | grep -q "KICK_STATUS=repo-invalid-format"; then
  echo "TEST 2 PASSED: repo-invalid-format detected"
else
  echo "TEST 2 FAILED"
  exit 1
fi

echo "ALL TESTS PASSED"
