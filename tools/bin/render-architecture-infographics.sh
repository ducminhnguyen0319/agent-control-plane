#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_HTML="${ROOT_DIR}/tools/architecture/architecture-infographics.html"
OUTPUT_DIR="${ROOT_DIR}/assets/architecture"
PDF_OUT="${OUTPUT_DIR}/agent-control-plane-architecture.pdf"
OVERVIEW_OUT="${OUTPUT_DIR}/overview-infographic.png"
RUNTIME_OUT="${OUTPUT_DIR}/runtime-loop-infographic.png"
LIFECYCLE_OUT="${OUTPUT_DIR}/worker-lifecycle-infographic.png"
STATE_OUT="${OUTPUT_DIR}/state-dashboard-infographic.png"

require_bin() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required dependency: $name" >&2
    exit 1
  fi
}

require_bin python3
require_bin playwright

PLAYWRIGHT_CLI="$(command -v playwright)"
PLAYWRIGHT_PACKAGE_ROOT="$(
  python3 - "$PLAYWRIGHT_CLI" <<'PY'
import os
import sys

print(os.path.dirname(os.path.realpath(sys.argv[1])))
PY
)"

mkdir -p "${OUTPUT_DIR}"
tmpdir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

cat >"${tmpdir}/render-architecture.js" <<'EOF'
const fs = require("fs");
const path = require("path");
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE_ROOT);

async function screenshotSection(page, selector, filename) {
  const element = await page.$(selector);
  if (!element) {
    throw new Error(`missing section for selector: ${selector}`);
  }
  await element.screenshot({ path: filename });
}

(async () => {
  const sourceHtml = process.env.ACP_ARCH_SOURCE_HTML;
  const pdfOut = process.env.ACP_ARCH_PDF_OUT;
  const overviewOut = process.env.ACP_ARCH_OVERVIEW_OUT;
  const runtimeOut = process.env.ACP_ARCH_RUNTIME_OUT;
  const lifecycleOut = process.env.ACP_ARCH_LIFECYCLE_OUT;
  const stateOut = process.env.ACP_ARCH_STATE_OUT;

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({
    viewport: { width: 1664, height: 964 },
    deviceScaleFactor: 1,
    colorScheme: "light",
  });

  await page.goto(`file://${sourceHtml}`, { waitUntil: "load" });
  await page.waitForTimeout(400);

  await screenshotSection(page, "#overview-page", overviewOut);
  await screenshotSection(page, "#runtime-loop-page", runtimeOut);
  await screenshotSection(page, "#worker-lifecycle-page", lifecycleOut);
  await screenshotSection(page, "#state-dashboard-page", stateOut);

  await page.pdf({
    path: pdfOut,
    printBackground: true,
    preferCSSPageSize: true,
    margin: {
      top: "0in",
      right: "0in",
      bottom: "0in",
      left: "0in",
    },
  });

  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
EOF

PLAYWRIGHT_PACKAGE_ROOT="${PLAYWRIGHT_PACKAGE_ROOT}" \
ACP_ARCH_SOURCE_HTML="${SOURCE_HTML}" \
ACP_ARCH_PDF_OUT="${PDF_OUT}" \
ACP_ARCH_OVERVIEW_OUT="${OVERVIEW_OUT}" \
ACP_ARCH_RUNTIME_OUT="${RUNTIME_OUT}" \
ACP_ARCH_LIFECYCLE_OUT="${LIFECYCLE_OUT}" \
ACP_ARCH_STATE_OUT="${STATE_OUT}" \
node "${tmpdir}/render-architecture.js"

echo "ARCHITECTURE_PDF=${PDF_OUT}"
echo "ARCHITECTURE_OVERVIEW_PNG=${OVERVIEW_OUT}"
echo "ARCHITECTURE_RUNTIME_PNG=${RUNTIME_OUT}"
echo "ARCHITECTURE_LIFECYCLE_PNG=${LIFECYCLE_OUT}"
echo "ARCHITECTURE_STATE_PNG=${STATE_OUT}"
