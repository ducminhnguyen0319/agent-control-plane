#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CLAUDE_USAGE_FILE="${ROOT_DIR}/tools/vendor/codex-quota/lib/claude-usage.js"
CLAUDE_README_FILE="${ROOT_DIR}/tools/vendor/codex-quota/README.md"
CLAUDE_DISPLAY_FILE="${ROOT_DIR}/tools/vendor/codex-quota/lib/display.js"

if rg -n "CLAUDE_COOKIE_DB_PATH|secret-tool|sqlite3|decryptChromeCookie|readClaudeCookiesFromDb|Browser cookies" \
  "${CLAUDE_USAGE_FILE}" "${CLAUDE_README_FILE}" "${CLAUDE_DISPLAY_FILE}" >/dev/null 2>&1; then
  echo "vendored codex-quota still contains browser-cookie Claude usage logic" >&2
  exit 1
fi

grep -q "Uses OAuth credentials only" "${CLAUDE_DISPLAY_FILE}"
grep -q "Claude usage in the bundled public package is OAuth-only." "${CLAUDE_README_FILE}"

node --input-type=module <<'EOF'
import { fetchClaudeUsageForCredentials, fetchClaudeUsage } from "./tools/vendor/codex-quota/lib/claude-usage.js";

const missingAccount = await fetchClaudeUsageForCredentials({ label: "demo", source: "test" });
if (missingAccount.success || missingAccount.error !== "Claude OAuth token required") {
  throw new Error(`unexpected credential fallback result: ${JSON.stringify(missingAccount)}`);
}

const missingOauth = await fetchClaudeUsage();
const oauthError = String(missingOauth.error || "").toLowerCase();
if (
  missingOauth.success ||
  (!oauthError.includes("oauth") && !oauthError.includes("credentials not found"))
) {
  throw new Error(`unexpected Claude usage fallback result: ${JSON.stringify(missingOauth)}`);
}
EOF

echo "vendored codex-quota Claude OAuth-only test passed"
