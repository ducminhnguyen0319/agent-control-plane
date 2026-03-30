#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_PACK_DIR=$(mktemp -d)
TMP_HOME=$(mktemp -d)
TMP_PLATFORM=$(mktemp -d)
TMP_OUTPUT=$(mktemp)

cleanup() {
  rm -rf "$TMP_PACK_DIR" "$TMP_HOME" "$TMP_PLATFORM"
  rm -f "$TMP_OUTPUT"
}
trap cleanup EXIT

cd "$ROOT_DIR"
npm pack --pack-destination "$TMP_PACK_DIR" >/dev/null
tarball_path=$(printf '%s\n' "$TMP_PACK_DIR"/agent-control-plane-*.tgz)

HOME="$TMP_HOME" AGENT_PLATFORM_HOME="$TMP_PLATFORM" \
  npx --yes --package "$tarball_path" agent-control-plane smoke >"$TMP_OUTPUT"

grep -q '^SMOKE_TEST_STATUS=ok$' "$TMP_OUTPUT"

echo "package smoke command test passed"
