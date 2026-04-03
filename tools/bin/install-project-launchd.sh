#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-project-launchd.sh --profile-id <id> [options]

Install a per-user LaunchAgent so one ACP project runtime starts automatically
after login/restart.

Options:
  --profile-id <id>       Installed profile id to manage
  --label <label>         Override LaunchAgent label (default: ai.agent.project.<id>)
  --delay-seconds <n>     Initial supervisor delay before first bootstrap (default: 0)
  --interval-seconds <n>  Supervisor interval between bootstrap passes (default: 15)
  --help                  Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

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

build_launchd_base_path() {
  local path_value="${ACP_PROJECT_RUNTIME_PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
  local tool_name=""
  local tool_dir=""

  for tool_name in node gh git python3 openclaw codex claude; do
    tool_dir="$(resolved_tool_dir "${tool_name}" || true)"
    append_path_dir path_value "${tool_dir}"
  done

  printf '%s\n' "${path_value}"
}

profile_id_override=""
label_override=""
delay_seconds="0"
interval_seconds="15"
profile_registry_root_override="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id_override="${2:-}"; shift 2 ;;
    --label) label_override="${2:-}"; shift 2 ;;
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

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "install-project-launchd.sh"; then
  exit 64
fi

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
if [[ ! -f "${CONFIG_YAML}" ]]; then
  printf 'profile not installed: %s\n' "${profile_id_override}" >&2
  exit 66
fi

PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
profile_slug="$(printf '%s' "${PROFILE_ID}" | tr -c 'A-Za-z0-9._-' '-')"
HOME_DIR="${ACP_PROJECT_RUNTIME_HOME_DIR:-${HOME:-}}"
SOURCE_HOME="${ACP_PROJECT_RUNTIME_SOURCE_HOME:-}"
if [[ -z "${SOURCE_HOME}" ]]; then
  if flow_is_skill_root "${FLOW_SKILL_DIR}"; then
    SOURCE_HOME="${FLOW_SKILL_DIR}"
  else
    SOURCE_HOME="$(cd "${FLOW_SKILL_DIR}/../../.." && pwd)"
  fi
fi
RUNTIME_HOME="${ACP_PROJECT_RUNTIME_RUNTIME_HOME:-${HOME_DIR}/.agent-runtime/runtime-home}"
WORKSPACE_DIR="${ACP_PROJECT_RUNTIME_WORKSPACE_DIR:-${HOME_DIR}/.agent-runtime/control-plane/workspace}"
PROFILE_REGISTRY_ROOT="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${HOME_DIR}/.agent-runtime/control-plane/profiles}}"
LAUNCH_AGENTS_DIR="${ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR:-${HOME_DIR}/Library/LaunchAgents}"
LOG_DIR="${ACP_PROJECT_RUNTIME_LOG_DIR:-${HOME_DIR}/.agent-runtime/logs}"
LABEL="${label_override:-${ACP_PROJECT_RUNTIME_LAUNCHD_LABEL:-ai.agent.project.${profile_slug}}}"
BASE_PATH="$(build_launchd_base_path)"
CODING_WORKER_OVERRIDE="${ACP_PROJECT_RUNTIME_CODING_WORKER:-${ACP_CODING_WORKER:-}}"
SYNC_SCRIPT="${ACP_PROJECT_RUNTIME_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/sync-shared-agent-home.sh}"
BOOTSTRAP_SCRIPT="${ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/project-launchd-bootstrap.sh}"
SUPERVISOR_SCRIPT="${ACP_PROJECT_RUNTIME_SUPERVISOR_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/project-runtime-supervisor.sh}"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
SUPERVISOR_PID_FILE="${STATE_ROOT}/runtime-supervisor.pid"
ENV_FILE="${ACP_PROJECT_RUNTIME_ENV_FILE:-${PROFILE_REGISTRY_ROOT}/${PROFILE_ID}/runtime.env}"
WRAPPER_PATH="${WORKSPACE_DIR}/bin/agent-project-${profile_slug}-launchd.sh"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
STDOUT_LOG="${LOG_DIR}/agent-project-${profile_slug}.stdout.log"
STDERR_LOG="${LOG_DIR}/agent-project-${profile_slug}.stderr.log"

if [[ -z "${HOME_DIR}" ]]; then
  echo "install-project-launchd requires HOME or ACP_PROJECT_RUNTIME_HOME_DIR" >&2
  exit 64
fi

mkdir -p "${WORKSPACE_DIR}/bin" "${LAUNCH_AGENTS_DIR}" "${LOG_DIR}" "$(dirname "${SUPERVISOR_PID_FILE}")"

cat >"${WRAPPER_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ACP_PROJECT_RUNTIME_HOME_DIR='${HOME_DIR}'
export ACP_PROJECT_RUNTIME_SOURCE_HOME='${SOURCE_HOME}'
export ACP_PROJECT_RUNTIME_RUNTIME_HOME='${RUNTIME_HOME}'
export ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT='${PROFILE_REGISTRY_ROOT}'
export ACP_PROJECT_RUNTIME_PROFILE_ID='${PROFILE_ID}'
export ACP_PROJECT_RUNTIME_ENV_FILE='${ENV_FILE}'
export ACP_PROJECT_ID='${PROFILE_ID}'
export AGENT_PROJECT_ID='${PROFILE_ID}'
export ACP_PROJECT_RUNTIME_PATH='${BASE_PATH}'
export ACP_PROJECT_RUNTIME_SYNC_SCRIPT='${SYNC_SCRIPT}'
export ACP_PROFILE_REGISTRY_ROOT='${PROFILE_REGISTRY_ROOT}'
EOF

if [[ -n "${CODING_WORKER_OVERRIDE}" ]]; then
  cat >>"${WRAPPER_PATH}" <<EOF
export ACP_CODING_WORKER='${CODING_WORKER_OVERRIDE}'
EOF
fi

cat >>"${WRAPPER_PATH}" <<EOF
exec bash '${SUPERVISOR_SCRIPT}' --bootstrap-script '${BOOTSTRAP_SCRIPT}' --pid-file '${SUPERVISOR_PID_FILE}' --delay-seconds '${delay_seconds}' --interval-seconds '${interval_seconds}'
EOF
chmod +x "${WRAPPER_PATH}"

cat >"${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProcessType</key>
	<string>Background</string>
	<key>ProgramArguments</key>
	<array>
		<string>${WRAPPER_PATH}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>WorkingDirectory</key>
	<string>${WORKSPACE_DIR}</string>
	<key>StandardErrorPath</key>
	<string>${STDERR_LOG}</string>
	<key>StandardOutPath</key>
	<string>${STDOUT_LOG}</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>HOME</key>
		<string>${HOME_DIR}</string>
		<key>PATH</key>
		<string>${BASE_PATH}</string>
		<key>ACP_PROFILE_REGISTRY_ROOT</key>
		<string>${PROFILE_REGISTRY_ROOT}</string>
	</dict>
</dict>
</plist>
EOF

if [[ "${ACP_PROJECT_RUNTIME_SKIP_LAUNCHCTL:-0}" == "1" ]]; then
  printf 'LAUNCHD_INSTALL_STATUS=skipped-launchctl\n'
  printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
  printf 'LABEL=%s\n' "${LABEL}"
  printf 'PLIST=%s\n' "${PLIST_PATH}"
  printf 'WRAPPER=%s\n' "${WRAPPER_PATH}"
  exit 0
fi

user_domain="gui/$(id -u)"
launchctl bootout "${user_domain}/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "${user_domain}" "${PLIST_PATH}"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if launchctl print "${user_domain}/${LABEL}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
launchctl kickstart -k "${user_domain}/${LABEL}" >/dev/null 2>&1 || true

printf 'LAUNCHD_INSTALL_STATUS=ok\n'
printf 'PROFILE_ID=%s\n' "${PROFILE_ID}"
printf 'LABEL=%s\n' "${LABEL}"
printf 'PLIST=%s\n' "${PLIST_PATH}"
printf 'WRAPPER=%s\n' "${WRAPPER_PATH}"
