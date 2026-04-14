#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PUBLISH_WORKFLOW="$ROOT_DIR/.github/workflows/publish.yml"

test -f "$PUBLISH_WORKFLOW"

for pattern in \
  "id-token: write" \
  "contents: read" \
  "name: Verify trusted publishing toolchain" \
  "git describe --tags --exact-match" \
  "npm publish --provenance --access public"; do
  if ! grep -Fq "$pattern" "$PUBLISH_WORKFLOW"; then
    echo "publish workflow missing required trust gate: $pattern" >&2
    exit 1
  fi
done

while IFS= read -r line; do
  if [[ "$line" == *"npm publish --access public"* && "$line" != *"--provenance"* ]]; then
    echo "publish workflow includes non-provenance publish command: $line" >&2
    exit 1
  fi
done < "$PUBLISH_WORKFLOW"

echo "publish workflow trust gates test passed"
