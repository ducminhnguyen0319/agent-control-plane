#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-project-systemd.sh --profile-id <id> [options]

Install a per-user systemd service so one ACP project runtime starts
automatically after login/restart on Linux.

Options:
  --profile-id <id>       Installed profile id to manage
  --unit-name <name>       Override systemd unit name (default: agent-project-<id>.service)
  --delay-seconds <n>      Initial supervisor delay before first bootstrap (default: 0)
  --interval-seconds <n>   Supervisor interval between bootstrap passes (default: 15)
  --help                   Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/flow-config-lib.sh"

append_path_dir() {
  local value_name="${1:?value name required}"
  local candidate="${2:-}"
  local current=""

  [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
  current="${!value_name:-}"
  case ":${current}:" in
    *":${candidate}:"*) return 0 ;;
  esac
  if [[ -n "${current}" ]]; then
    printf -v "${value_name}" '%s:%s' "${current}" "${candidate}"
  else
    printf -v "${value_name}" '%s' "${candidate}"
  fi
}

resolved_tool_dir() {
  local tool_name="${1:-}"
  local tool_path=""

  [[ -n "${tool_name}" ]] || return 1
  tool_path="$(command -v "${tool_name}" 2>/dev/null || true)"
  [[ -n "${tool_path}" ]] || return 1
  dirname "${tool_path}"
}

build_systemd_base_path() {
  local path_value="${ACP_PROJECT_RUNTIME_PATH:-/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
  local tool_name=""
  local tool_dir=""

  for tool_name in node gh git python3 openclaw codex claude ollama pi crush kilo; do
    tool_dir="$(resolved_tool_dir "${tool_name}" || true)"
    append_path_dir path_value "${tool_dir}"
  done

  printf '%s\n' "${path_value}"
}

profile_id_override=""
unit_name_override=""
delay_seconds="0"
interval_seconds="15"
profile_registry_root_override="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id_override="${2:-}"; shift 2 ;;
    --unit-name) unit_name_override="${2:-}"; shift 2 ;;
    --delay-seconds) delay_seconds="${2:-}"; shift 2 ;;
    --interval-seconds) interval_seconds="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "${profile_id_override}" ]]; then
  usage >&2
  exit 64
fi

case "${delay_seconds}" in
  ''|*[!0-9]*) echo "--delay-seconds must be numeric" >&2; exit 64 ;;
esac

case "${interval_seconds}" in
  ''|*[!0-9]*) echo "--interval-seconds must be numeric" >&2; exit 64 ;;
esac

export ACP_PROJECT_ID="${profile_id_override}"
export AGENT_PROJECT_ID="${profile_id_override}"

if [[ -n "${profile_registry_root_override}" ]]; then
  export ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root_override}"
fi

flow_skill_dir="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${flow_skill_dir}" "install-project-systemd.sh"; then
  exit 64
fi

config_yaml="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
if [[ ! -f "${config_yaml}" ]]; then
  printf 'profile not installed: %s\n' "${profile_id_override}" >&2
  exit 66
fi

profile_id="$(flow_resolve_adapter_id "${config_yaml}")"
profile_slug="$(printf '%s' "${profile_id}" | tr -c 'A-Za-z0-9._-' '-')"
home_dir="${ACP_PROJECT_RUNTIME_HOME_DIR:-${HOME:-}}"
source_home="${ACP_PROJECT_RUNTIME_SOURCE_HOME:-}"

if [[ -z "${source_home}" ]]; then
  if flow_is_skill_root "${flow_skill_dir}"; then
    source_home="${flow_skill_dir}"
  else
    source_home="$(cd "${flow_skill_dir}/../../.." && pwd)"
  fi
fi

runtime_home="${ACP_PROJECT_RUNTIME_RUNTIME_HOME:-${home_dir}/.agent-runtime/runtime-home}"
workspace_dir="${ACP_PROJECT_RUNTIME_WORKSPACE_DIR:-${home_dir}/.agent-runtime/control-plane/workspace}"
profile_registry_root="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${home_dir}/.agent-runtime/control-plane/profiles}}"
systemd_dir="${ACP_PROJECT_RUNTIME_SYSTEMD_DIR:-${home_dir}/.config/systemd/user}"
log_dir="${ACP_PROJECT_RUNTIME_LOG_DIR:-${home_dir}/.agent-runtime/logs}"
unit_name="${unit_name_override:-${ACP_PROJECT_RUNTIME_SYSTEMD_UNIT:-agent-project-${profile_slug}.service}}"
base_path="$(build_systemd_base_path)"
coding_worker_override="${ACP_PROJECT_RUNTIME_CODING_WORKER:-${ACP_CODING_WORKER:-}}"
sync_script="${ACP_PROJECT_RUNTIME_SYNC_SCRIPT:-${flow_skill_dir}/tools/bin/sync-shared-agent-home.sh}"
runtime_skill_dir="${runtime_home}/skills/openclaw/agent-control-plane"
bootstrap_script="${ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT:-}"

if [[ -z "${bootstrap_script}" ]]; then
  if [[ -x "${runtime_skill_dir}/tools/bin/project-systemd-bootstrap.sh" ]]; then
    bootstrap_script="${runtime_skill_dir}/tools/bin/project-systemd-bootstrap.sh"
  else
    bootstrap_script="${flow_skill_dir}/tools/bin/project-systemd-bootstrap.sh"
  fi
fi

supervisor_script="${ACP_PROJECT_RUNTIME_SUPERVISOR_SCRIPT:-}"
if [[ -z "${supervisor_script}" ]]; then
  if [[ -x "${runtime_skill_dir}/tools/bin/project-runtime-supervisor.sh" ]]; then
    supervisor_script="${runtime_skill_dir}/tools/bin/project-runtime-supervisor.sh"
  else
    supervisor_script="${flow_skill_dir}/tools/bin/project-runtime-supervisor.sh"
  fi
fi

state_root="$(flow_resolve_state_root "${config_yaml}")"
supervisor_pid_file="${state_root}/runtime-supervisor.pid"
env_file="${ACP_PROJECT_RUNTIME_ENV_FILE:-${profile_registry_root}/${profile_id}/runtime.env}"
wrapper_path="${workspace_dir}/bin/agent-project-${profile_slug}-systemd.sh"
unit_file="${systemd_dir}/${unit_name}"
stdout_log="${log_dir}/agent-project-${profile_slug}.stdout.log"
stderr_log="${log_dir}/agent-project-${profile_slug}.stderr.log"

if [[ -z "${home_dir}" ]]; then
  echo "install-project-systemd requires HOME or ACP_PROJECT_RUNTIME_HOME_DIR" >&2
  exit 64
fi

# Check if systemd is available
if ! command -v systemctl &>/dev/null; then
  echo "systemctl not found. Is systemd installed?" >&2
  exit 1
fi

mkdir -p "${workspace_dir}/bin" "${systemd_dir}" "${log_dir}" "$(dirname "${supervisor_pid_file}")"

# Create wrapper script
cat >"${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ACP_PROJECT_RUNTIME_HOME_DIR='${home_dir}'
export ACP_PROJECT_RUNTIME_SOURCE_HOME='${source_home}'
export ACP_PROJECT_RUNTIME_RUNTIME_HOME='${runtime_home}'
export ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT='${profile_registry_root}'
export ACP_PROJECT_RUNTIME_PROFILE_ID='${profile_id}'
export ACP_PROJECT_RUNTIME_ENV_FILE='${env_file}'
export ACP_PROJECT_ID='${profile_id}'
export AGENT_PROJECT_ID='${profile_id}'
export ACP_PROJECT_RUNTIME_PATH='${base_path}'
export ACP_PROJECT_RUNTIME_SYNC_SCRIPT='${sync_script}'
export ACP_PROFILE_REGISTRY_ROOT='${profile_registry_root}'
EOF

if [[ -n "${coding_worker_override}" ]]; then
  cat >>"${wrapper_path}" <<EOF
export ACP_CODING_WORKER='${coding_worker_override}'
EOF
fi

cat >>"${wrapper_path}" <<EOF
exec bash '${supervisor_script}' --bootstrap-script '${bootstrap_script}' --pid-file '${supervisor_pid_file}' --delay-seconds '${delay_seconds}' --interval-seconds '${interval_seconds}'
EOF
chmod +x "${wrapper_path}"

# Create systemd unit file
cat >"${unit_file}" <<EOF
[Unit]
Description=Agent Control Plane - Project ${profile_id}
After=default.target
Wants=default.target

[Service]
Type=simple
ExecStart=${wrapper_path}
WorkingDirectory=${workspace_dir}
StandardOutput=append:${stdout_log}
StandardError=append:${stderr_log}
Restart=always
RestartSec=10
Environment=HOME=${home_dir}
Environment=PATH=${base_path}
Environment=ACP_PROFILE_REGISTRY_ROOT=${profile_registry_root}

[Install]
WantedBy=default.target
EOF

# Enable and start the service
if [[ "${ACP_PROJECT_RUNTIME_SKIP_SYSTEMCTL:-0}" == "1" ]]; then
  printf 'SYSTEMD_INSTALL_STATUS=skipped-systemctl\n'
  printf 'PROFILE_ID=%s\n' "${profile_id}"
  printf 'UNIT_NAME=%s\n' "${unit_name}"
  printf 'UNIT_FILE=%s\n' "${unit_file}"
  printf 'WRAPPER=%s\n' "${wrapper_path}"
  exit 0
fi

# Enable user service (create symlink)
systemctl --user enable "${unit_name}" 2>&1 || true

# Start the service
systemctl --user restart "${unit_name}" 2>&1 || true

# Wait briefly for service to start
for _ in $(seq 1 10); do
  if systemctl --user is-active --quiet "${unit_name}" 2>/dev/null; then
    break
  fi
  sleep 1
done

printf 'SYSTEMD_INSTALL_STATUS=ok\n'
printf 'PROFILE_ID=%s\n' "${profile_id}"
printf 'UNIT_NAME=%s\n' "${unit_name}"
printf 'UNIT_FILE=%s\n' "${unit_file}"
printf 'WRAPPER=%s\n' "${wrapper_path}"
