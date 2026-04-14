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
const entriesByPath = new Map((pack.files || []).map((entry) => [entry.path, entry]));

function fail(message) {
  console.error(message);
  process.exit(1);
}

for (const forbiddenPath of [
  "SKILL.md",
  "tools/tests/test-agent-control-plane-npm-cli.sh",
  "tools/bin/render-dashboard-demo-media.sh",
  "tools/bin/render-architecture-infographics.sh",
  "tools/vendor/codex-quota/README.md",
  "tools/bin/audit-agent-worktrees.sh",
  "tools/bin/audit-issue-routing.sh",
  "tools/bin/audit-retained-layout.sh",
  "tools/bin/audit-retained-overlap.sh",
  "tools/bin/audit-retained-worktrees.sh",
  "tools/bin/check-skill-contracts.sh",
  "bin/audit-issue-routing.sh",
  "tools/templates/legacy/issue-prompt-template-pre-slim.md",
  "tools/bin/render-dashboard-snapshot.py",
  "references/commands.md",
  "references/control-plane-map.md",
  "references/docs-map.md",
  "references/repo-map.md",
  "references/architecture.md",
]) {
  if (paths.has(forbiddenPath)) {
    fail(`forbidden tarball path present: ${forbiddenPath}`);
  }
}

for (const requiredPath of [
  "bin/agent-control-plane",
  "npm/bin/agent-control-plane.js",
  "tools/bin/test-smoke.sh",
  "tools/dashboard/app.js",
  "tools/vendor/codex-quota/codex-quota.js",
]) {
  if (!paths.has(requiredPath)) {
    fail(`required tarball path missing: ${requiredPath}`);
  }
}

for (const executablePath of [
  "bin/agent-control-plane",
  "bin/issue-resource-class.sh",
  "bin/label-follow-up-issues.sh",
  "bin/pr-risk.sh",
  "bin/sync-pr-labels.sh",
  "npm/bin/agent-control-plane.js",
  "tools/bin/test-smoke.sh",
]) {
  const entry = entriesByPath.get(executablePath);
  if (!entry || (entry.mode & 0o111) === 0) {
    fail(`required executable tarball path missing or non-executable: ${executablePath}`);
  }
}

const result = {
  version: pack.version,
  size: pack.size,
  unpackedSize: pack.unpackedSize,
  entryCount: pack.entryCount,
};

console.log(JSON.stringify(result));

// Compressed-size budget guard: fail if the tarball creeps above 400 KB.
if (pack.size > 400 * 1024) {
  fail(`tarball compressed size ${Math.round(pack.size / 1024)} KB exceeds 400 KB budget`);
}
NODE

TMP_PACKAGE_JSON=$(mktemp)
tar -xOf "$TMP_PACK_DIR"/agent-control-plane-*.tgz package/package.json >"$TMP_PACKAGE_JSON"

node - "$TMP_PACKAGE_JSON" <<'NODE'
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const expectedFunding = "https://github.com/sponsors/ducminhnguyen0319";

if (!pkg.bin || pkg.bin["agent-control-plane"] !== "./bin/agent-control-plane") {
  console.error("tarball package.json missing executable bin entry");
  process.exit(1);
}

if (!pkg.publishConfig || pkg.publishConfig.access !== "public" || pkg.publishConfig.provenance !== true) {
  console.error("tarball package.json missing trusted publishing metadata");
  process.exit(1);
}

if (pkg.homepage !== "https://github.com/ducminhnguyen0319/agent-control-plane") {
  console.error("tarball package.json has unexpected homepage");
  process.exit(1);
}

if (!pkg.bugs || pkg.bugs.url !== "https://github.com/ducminhnguyen0319/agent-control-plane/issues") {
  console.error("tarball package.json has unexpected bugs URL");
  process.exit(1);
}

if (!pkg.repository || pkg.repository.type !== "git" || pkg.repository.url !== "git+https://github.com/ducminhnguyen0319/agent-control-plane.git") {
  console.error("tarball package.json has unexpected repository");
  process.exit(1);
}

if (!Array.isArray(pkg.funding) || !pkg.funding.includes(expectedFunding)) {
  console.error("tarball package.json missing expected funding link");
  process.exit(1);
}

for (const keyword of ["runtime", "dashboard", "agents"]) {
  if (!Array.isArray(pkg.keywords) || !pkg.keywords.includes(keyword)) {
    console.error(`tarball package.json missing expected keyword: ${keyword}`);
    process.exit(1);
  }
}
NODE

echo "package tarball surface test passed"
