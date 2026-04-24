#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flow_skill_dir="$(cd "${script_dir}/../.." && pwd)"
home_dir="${ACP_PROJECT_RUNTIME_HOME_DIR:-${HOME:-}}"
profile_registry_root="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${home_dir}/.agent-runtime/control-plane/profiles}}"
profile_id="${ACP_PROJECT_RUNTIME_PROFILE_ID:-${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-}}}"
env_file="${ACP_PROJECT_RUNTIME_ENV_FILE:-${profile_registry_root}/${profile_id}/runtime.env}"

if [[ -z "${home_dir}" ]]; then
  echo "project systemd bootstrap requires HOME or ACP_PROJECT_RUNTIME_HOME_DIR" >&2
  exit 64
fi

if [[ -z "${profile_id}" ]]; then
  echo "project systemd bootstrap requires ACP_PROJECT_RUNTIME_PROFILE_ID or ACP_PROJECT_ID" >&2
  exit 64
fi

export HOME="${home_dir}"
export ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}"
export ACP_PROJECT_ID="${profile_id}"
export AGENT_PROJECT_ID="${profile_id}"

if [[ -f "${env_file}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${env_file}"
  set +a
fi

# Resolve launch paths after runtime.env overrides are loaded so systemd can
# pin the project runtime to a source checkout or alternate runtime home.
source_home="${ACP_PROJECT_RUNTIME_SOURCE_HOME:-}"
runtime_home="${ACP_PROJECT_RUNTIME_RUNTIME_HOME:-${home_dir}/.agent-runtime/runtime-home}"
base_path="${ACP_PROJECT_RUNTIME_PATH:-/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
sync_script="${ACP_PROJECT_RUNTIME_SYNC_SCRIPT:-${flow_skill_dir}/tools/bin/sync-shared-agent-home.sh}"
ensure_sync_script="${ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT:-${flow_skill_dir}/tools/bin/ensure-runtime-sync.sh}"
runtime_heartbeat_script="${ACP_PROJECT_RUNTIME_HEARTBEAT_SCRIPT:-${runtime_home}/skills/openclaw/agent-control-plane/tools/bin/heartbeat-safe-auto.sh}"
always_sync="${ACP_PROJECT_RUNTIME_ALWAYS_SYNC:-0}"
export PATH="${base_path}"

if [[ ! -x "${ensure_sync_script}" && ! -x "${sync_script}" ]]; then
  echo "project systemd bootstrap missing sync helper: ${ensure_sync_script}" >&2
  exit 65
fi

if [[ -x "${ensure_sync_script}" ]]; then
  ensure_args=(--runtime-home "${runtime_home}" --quiet)
  if [[ -n "${source_home}" ]]; then
    ensure_args=(--source-home "${source_home}" "${ensure_args[@]}")
  fi
  if [[ "${always_sync}" == "1" ]]; then
    ensure_args=(--force "${ensure_args[@]}")
  fi
  if [[ "${flow_skill_dir}" == "${runtime_home}"/* ]]; then
    printf 'RUNTIME_SYNC_SKIPPED=active-runtime-home\n'
  else
    bash "${ensure_sync_script}" "${ensure_args[@]}"
  fi
elif [[ "${always_sync}" == "1" || ! -x "${runtime_heartbeat_script}" ]]; then
  if [[ -z "${source_home}" ]]; then
    source_home="${flow_skill_dir}"
  fi
  bash "${sync_script}" "${source_home}" "${runtime_home}" >/dev/null
fi

if [[ ! -x "${runtime_heartbeat_script}" ]]; then
  echo "project systemd bootstrap missing runtime heartbeat: ${runtime_heartbeat_script}" >&2
  exit 66
fi

exec bash "${runtime_heartbeat_script}"
