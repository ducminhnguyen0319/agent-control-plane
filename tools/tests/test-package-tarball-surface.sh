#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_JSON=$(mktemp)
TMP_PACK_DIR=$(mktemp -d)
TMP_PACKAGE_JSON=""
cleanup() {
  rm -f "$TMP_JSON"
  if [[ -n "$TMP_PACKAGE_JSON" ]]; then
    rm -f "$TMP_PACKAGE_JSON"
  fi
  rm -rf "$TMP_PACK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
npm pack --json --dry-run >"$TMP_JSON"
npm pack --pack-destination "$TMP_PACK_DIR" >/dev/null

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
  "bin/agent-control-plane",
  "npm/bin/agent-control-plane.js",
  "references/commands.md",
  "references/control-plane-map.md",
  "references/docs-map.md",
  "references/repo-map.md",
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

TMP_PACKAGE_JSON=$(mktemp)
tar -xOf "$TMP_PACK_DIR"/agent-control-plane-*.tgz package/package.json >"$TMP_PACKAGE_JSON"

node - "$TMP_PACKAGE_JSON" <<'NODE'
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));

if (!pkg.bin || pkg.bin["agent-control-plane"] !== "./bin/agent-control-plane") {
  console.error("tarball package.json missing executable bin entry");
  process.exit(1);
}
NODE

echo "package tarball surface test passed"
