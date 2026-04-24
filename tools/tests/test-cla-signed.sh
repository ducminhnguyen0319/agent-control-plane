#!/usr/bin/env bash
# test-cla-signed.sh
# Check if PR description (from file) contains CLA agreement text
# Usage: test-cla-signed.sh PR_DESCRIPTION_FILE

set -euo pipefail

PR_DESC_FILE="${1:?usage: test-cla-signed.sh PR_DESCRIPTION_FILE}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! -f "$PR_DESC_FILE" ]]; then
  echo "SKIP: No PR description file provided (not in PR context)"
  exit 0
fi

# Check for CLA agreement text in PR description
if grep -qi "I have read the CLA" "$PR_DESC_FILE" || \
   grep -qi "I have read.*CLA" "$PR_DESC_FILE" || \
   grep -qi "agree to its terms" "$PR_DESC_FILE"; then
  echo "PASS: CLA agreement found in PR description"
  exit 0
else
  echo "FAIL: CLA agreement not found in PR description"
  echo "Please add: 'I have read the CLA (https://github.com/ducminhnguyen0319/agent-control-plane/blob/main/CLA.md) and I agree to its terms.'"
  exit 1
fi
