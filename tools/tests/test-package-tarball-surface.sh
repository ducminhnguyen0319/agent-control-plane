#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_JSON=$(mktemp)
trap 'rm -f "$TMP_JSON"' EXIT

cd "$ROOT_DIR"
npm pack --json --dry-run >"$TMP_JSON"

node - "$TMP_JSON" <<'NODE'
const fs = require("fs");

const reportPath = process.argv[2];
const pack = JSON.parse(fs.readFileSync(reportPath, "utf8"))[0];
const paths = new Set((pack.files || []).map((entry) => entry.path));

function fail(message) {
  console.error(message);
  process.exit(1);
}

for (const forbiddenPath of [
  "tools/tests/test-agent-control-plane-npm-cli.sh",
  "tools/bin/render-dashboard-demo-media.sh",
  "tools/bin/render-architecture-infographics.sh",
  "tools/vendor/codex-quota/README.md",
]) {
  if (paths.has(forbiddenPath)) {
    fail(`forbidden tarball path present: ${forbiddenPath}`);
  }
}

for (const requiredPath of [
  "npm/public-bin/agent-control-plane",
  "npm/bin/agent-control-plane.js",
  "tools/bin/test-smoke.sh",
  "tools/dashboard/app.js",
  "tools/vendor/codex-quota/codex-quota.js",
]) {
  if (!paths.has(requiredPath)) {
    fail(`required tarball path missing: ${requiredPath}`);
  }
}

const result = {
  version: pack.version,
  size: pack.size,
  unpackedSize: pack.unpackedSize,
  entryCount: pack.entryCount,
};

console.log(JSON.stringify(result));
NODE

echo "package tarball surface test passed"
