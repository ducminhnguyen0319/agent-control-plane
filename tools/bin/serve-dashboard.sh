#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIREMENTS="${SCRIPT_DIR}/../dashboard/requirements.txt"

# Check Python dependencies
check_dep() {
  python3 -c "import $1" 2>/dev/null && return 0
  echo "Missing Python dependency: $1" >&2
  if [[ -f "${REQUIREMENTS}" ]]; then
    echo "Install with: pip3 install -r ${REQUIREMENTS}" >&2
  fi
  return 1
}

check_dep "aiohttp" || exit 1
check_dep "aiohttp_cors" || exit 1
check_dep "websockets" || exit 1

exec python3 "${SCRIPT_DIR}/../dashboard/server.py" "$@"
