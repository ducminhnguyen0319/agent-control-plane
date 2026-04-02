#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOME_DIR="${ACP_DASHBOARD_HOME_DIR:-${HOME:-}}"
SOURCE_HOME="${ACP_DASHBOARD_SOURCE_HOME:-}"
RUNTIME_HOME="${ACP_DASHBOARD_RUNTIME_HOME:-${HOME_DIR}/.agent-runtime/runtime-home}"
PROFILE_REGISTRY_ROOT="${ACP_DASHBOARD_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${HOME_DIR}/.agent-runtime/control-plane/profiles}}"
HOST="${ACP_DASHBOARD_HOST:-127.0.0.1}"
PORT="${ACP_DASHBOARD_PORT:-8765}"
BASE_PATH="${ACP_DASHBOARD_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
SYNC_SCRIPT="${ACP_DASHBOARD_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/sync-shared-agent-home.sh}"
ENSURE_SYNC_SCRIPT="${ACP_DASHBOARD_ENSURE_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/ensure-runtime-sync.sh}"
RUNTIME_SERVE_SCRIPT="${ACP_DASHBOARD_RUNTIME_SERVE_SCRIPT:-${RUNTIME_HOME}/skills/openclaw/agent-control-plane/tools/bin/serve-dashboard.sh}"

if [[ -z "${HOME_DIR}" ]]; then
  echo "dashboard launchd bootstrap requires HOME or ACP_DASHBOARD_HOME_DIR" >&2
  exit 64
fi

export HOME="${HOME_DIR}"
export PATH="${BASE_PATH}"
export ACP_PROFILE_REGISTRY_ROOT="${PROFILE_REGISTRY_ROOT}"
export PYTHONDONTWRITEBYTECODE=1

if [[ ! -x "${ENSURE_SYNC_SCRIPT}" && ! -x "${SYNC_SCRIPT}" ]]; then
  echo "dashboard launchd bootstrap missing sync helper: ${ENSURE_SYNC_SCRIPT}" >&2
  exit 65
fi

if [[ -x "${ENSURE_SYNC_SCRIPT}" ]]; then
  ensure_args=(--runtime-home "${RUNTIME_HOME}" --quiet)
  if [[ -n "${SOURCE_HOME}" ]]; then
    ensure_args=(--source-home "${SOURCE_HOME}" "${ensure_args[@]}")
  fi
  bash "${ENSURE_SYNC_SCRIPT}" "${ensure_args[@]}"
else
  if [[ -z "${SOURCE_HOME}" ]]; then
    SOURCE_HOME="${FLOW_SKILL_DIR}"
  fi
  bash "${SYNC_SCRIPT}" "${SOURCE_HOME}" "${RUNTIME_HOME}" >/dev/null
fi

if [[ ! -x "${RUNTIME_SERVE_SCRIPT}" ]]; then
  echo "dashboard launchd bootstrap missing runtime serve script: ${RUNTIME_SERVE_SCRIPT}" >&2
  exit 66
fi

exec bash "${RUNTIME_SERVE_SCRIPT}" --host "${HOST}" --port "${PORT}"
