#!/usr/bin/env bash
set -euo pipefail

PR_NUMBER="${1:?usage: start-pr-merge-repair-worker.sh PR_NUMBER [safe|bypass]}"
MODE="${2:-safe}"
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"${WORKSPACE_DIR}/bin/start-pr-fix-worker.sh" "$PR_NUMBER" "$MODE" merge-repair
