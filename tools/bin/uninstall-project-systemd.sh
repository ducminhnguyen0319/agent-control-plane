#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  uninstall-project-systemd.sh --profile-id <id> [options]

Remove a previously installed systemd user service for an ACP project.

Options:
  --profile-id <id>       Installed profile id to manage
  --unit-name <name>       Override systemd unit name (default: agent-project-<id>.service)
  --help                   Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/flow-config-lib.sh"

profile_id_override=""
unit_name_override=""
profile_registry_root_override="${ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id_override="${2:-}"; shift 2 ;;
    --unit-name) unit_name_override="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "${profile_id_override}" ]]; then
  usage >&2
  exit 64
fi

export ACP_PROJECT_ID="${profile_id_override}"
export AGENT_PROJECT_ID="${profile_id_override}"

if [[ -n "${profile_registry_root_override}" ]]; then
  export ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root_override}"
fi

flow_skill_dir="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${flow_skill_dir}" "uninstall-project-systemd.sh"; then
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
systemd_dir="${ACP_PROJECT_RUNTIME_SYSTEMD_DIR:-${home_dir}/.config/systemd/user}"
unit_name="${unit_name_override:-${ACP_PROJECT_RUNTIME_SYSTEMD_UNIT:-agent-project-${profile_slug}.service}}"
unit_file="${systemd_dir}/${unit_name}"
workspace_dir="${ACP_PROJECT_RUNTIME_WORKSPACE_DIR:-${home_dir}/.agent-runtime/control-plane/workspace}"
wrapper_path="${workspace_dir}/bin/agent-project-${profile_slug}-systemd.sh"

# Check if systemd is available
if ! command -v systemctl &>/dev/null; then
  echo "systemctl not found. Is systemd installed?" >&2
  exit 1
fi

# Stop and disable the service
"${SYSTEMCTL_BIN}" --user stop "${unit_name}" 2>&1 || true
"${SYSTEMCTL_BIN}" --user disable "${unit_name}" 2>&1 || true

# Remove unit file
rm -f "${unit_file}"

# Remove wrapper script
rm -f "${wrapper_path}"

printf 'SYSTEMD_UNINSTALL_STATUS=ok\n'
printf 'PROFILE_ID=%s\n' "${profile_id}"
printf 'UNIT_NAME=%s\n' "${unit_name}"
printf 'UNIT_FILE=%s\n' "${unit_file}"
printf 'WRAPPER=%s\n' "${wrapper_path}"
