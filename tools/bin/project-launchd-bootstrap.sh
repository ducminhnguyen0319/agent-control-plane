#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOME_DIR="${ACP_PROJECT_RUNTIME_HOME_DIR:-${HOME:-}}"
PROFILE_REGISTRY_ROOT="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${HOME_DIR}/.agent-runtime/control-plane/profiles}}"
PROFILE_ID="${ACP_PROJECT_RUNTIME_PROFILE_ID:-${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-}}}"
ENV_FILE="${ACP_PROJECT_RUNTIME_ENV_FILE:-${PROFILE_REGISTRY_ROOT}/${PROFILE_ID}/runtime.env}"

if [[ -z "${HOME_DIR}" ]]; then
  echo "project launchd bootstrap requires HOME or ACP_PROJECT_RUNTIME_HOME_DIR" >&2
  exit 64
fi

if [[ -z "${PROFILE_ID}" ]]; then
  echo "project launchd bootstrap requires ACP_PROJECT_RUNTIME_PROFILE_ID or ACP_PROJECT_ID" >&2
  exit 64
fi

export HOME="${HOME_DIR}"
export ACP_PROFILE_REGISTRY_ROOT="${PROFILE_REGISTRY_ROOT}"
export ACP_PROJECT_ID="${PROFILE_ID}"
export AGENT_PROJECT_ID="${PROFILE_ID}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

# Resolve launch paths after runtime.env overrides are loaded so launchd can
# pin the project runtime to a source checkout or alternate runtime home.
SOURCE_HOME="${ACP_PROJECT_RUNTIME_SOURCE_HOME:-}"
RUNTIME_HOME="${ACP_PROJECT_RUNTIME_RUNTIME_HOME:-${HOME_DIR}/.agent-runtime/runtime-home}"
BASE_PATH="${ACP_PROJECT_RUNTIME_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
SYNC_SCRIPT="${ACP_PROJECT_RUNTIME_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/sync-shared-agent-home.sh}"
ENSURE_SYNC_SCRIPT="${ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/ensure-runtime-sync.sh}"
RUNTIME_HEARTBEAT_SCRIPT="${ACP_PROJECT_RUNTIME_HEARTBEAT_SCRIPT:-${RUNTIME_HOME}/skills/openclaw/agent-control-plane/tools/bin/heartbeat-safe-auto.sh}"
ALWAYS_SYNC="${ACP_PROJECT_RUNTIME_ALWAYS_SYNC:-0}"
export PATH="${BASE_PATH}"

if [[ ! -x "${ENSURE_SYNC_SCRIPT}" && ! -x "${SYNC_SCRIPT}" ]]; then
  echo "project launchd bootstrap missing sync helper: ${ENSURE_SYNC_SCRIPT}" >&2
  exit 65
fi

if [[ -x "${ENSURE_SYNC_SCRIPT}" ]]; then
  ensure_args=(--runtime-home "${RUNTIME_HOME}" --quiet)
  if [[ -n "${SOURCE_HOME}" ]]; then
    ensure_args=(--source-home "${SOURCE_HOME}" "${ensure_args[@]}")
  fi
  if [[ "${ALWAYS_SYNC}" == "1" ]]; then
    ensure_args=(--force "${ensure_args[@]}")
  fi
  bash "${ENSURE_SYNC_SCRIPT}" "${ensure_args[@]}"
elif [[ "${ALWAYS_SYNC}" == "1" || ! -x "${RUNTIME_HEARTBEAT_SCRIPT}" ]]; then
  if [[ -z "${SOURCE_HOME}" ]]; then
    SOURCE_HOME="${FLOW_SKILL_DIR}"
  fi
  bash "${SYNC_SCRIPT}" "${SOURCE_HOME}" "${RUNTIME_HOME}" >/dev/null
fi

if [[ ! -x "${RUNTIME_HEARTBEAT_SCRIPT}" ]]; then
  echo "project launchd bootstrap missing runtime heartbeat: ${RUNTIME_HEARTBEAT_SCRIPT}" >&2
  exit 66
fi

exec bash "${RUNTIME_HEARTBEAT_SCRIPT}"
