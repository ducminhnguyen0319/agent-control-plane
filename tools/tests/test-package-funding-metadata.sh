#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PACKAGE_JSON="$ROOT_DIR/package.json"
FUNDING_FILE="$ROOT_DIR/.github/FUNDING.yml"

node -e '
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(pkg.funding) || pkg.funding.length === 0) {
  process.exit(1);
}
if (!pkg.funding.includes("https://github.com/sponsors/ducminhnguyen0319")) {
  process.exit(2);
}
' "$PACKAGE_JSON"

test -f "$FUNDING_FILE"
grep -q '^github: \[ducminhnguyen0319\]$' "$FUNDING_FILE"
grep -q '^  - https://github.com/sponsors/ducminhnguyen0319$' "$FUNDING_FILE"
