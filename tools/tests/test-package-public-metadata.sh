#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PACKAGE_JSON="$ROOT_DIR/package.json"

node -e '
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));

if (!pkg.description || !pkg.description.includes("running reliably without constant human babysitting")) {
  process.exit(1);
}
if (pkg.homepage !== "https://github.com/ducminhnguyen0319/agent-control-plane") {
  process.exit(10);
}
if (!pkg.bugs || pkg.bugs.url !== "https://github.com/ducminhnguyen0319/agent-control-plane/issues") {
  process.exit(11);
}
if (!pkg.repository || pkg.repository.type !== "git" || pkg.repository.url !== "git+https://github.com/ducminhnguyen0319/agent-control-plane.git") {
  process.exit(12);
}
if (pkg.license !== "MIT") {
    process.exit(2);
}
if (!pkg.publishConfig || pkg.publishConfig.access !== "public" || pkg.publishConfig.provenance !== true) {
  process.exit(13);
}
for (const keyword of ["agents", "dashboard", "runtime"]) {
  if (!Array.isArray(pkg.keywords) || !pkg.keywords.includes(keyword)) {
    process.exit(3);
  }
}
if (!Array.isArray(pkg.files) || !pkg.files.includes("assets/workflow-catalog.json")) {
  process.exit(4);
}
if (pkg.files.includes("assets")) {
  process.exit(5);
}
if (pkg.files.includes("tools/tests")) {
  process.exit(13);
}
if (!pkg.bin || pkg.bin["agent-control-plane"] !== "./bin/agent-control-plane") {
  process.exit(8);
}
const requiredBinPaths = [
  "bin/agent-control-plane",
  "bin/issue-resource-class.sh",
  "bin/label-follow-up-issues.sh",
  "bin/pr-risk.sh",
  "bin/sync-pr-labels.sh"
];
for (const binPath of requiredBinPaths) {
  if (!Array.isArray(pkg.files) || !pkg.files.includes(binPath)) {
    process.exit(7);
  }
}
for (const bundledPath of [
  "tools/vendor/codex-quota/codex-quota.js",
  "tools/vendor/codex-quota/lib",
  "tools/vendor/codex-quota-manager/scripts"
]) {
  if (!pkg.files.includes(bundledPath)) {
    process.exit(9);
  }
}
' "$PACKAGE_JSON"

test -f "$ROOT_DIR/LICENSE"
grep -q '^MIT License$' "$ROOT_DIR/LICENSE"
test -f "$ROOT_DIR/bin/agent-control-plane"
test -x "$ROOT_DIR/bin/agent-control-plane"

echo "package public metadata test passed"
