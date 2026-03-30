#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  uninstall-project-launchd.sh --profile-id <id> [options]

Remove the per-user LaunchAgent for one ACP project runtime.

Options:
  --profile-id <id>  Installed profile id to manage
  --label <label>    Override LaunchAgent label (default: ai.agent.project.<id>)
  --help             Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

profile_id=""
label_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id="${2:-}"; shift 2 ;;
    --label) label_override="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "${profile_id}" ]]; then
  usage >&2
  exit 64
fi

HOME_DIR="${ACP_PROJECT_RUNTIME_HOME_DIR:-${HOME:-}}"
WORKSPACE_DIR="${ACP_PROJECT_RUNTIME_WORKSPACE_DIR:-${HOME_DIR}/.agent-runtime/control-plane/workspace}"
LAUNCH_AGENTS_DIR="${ACP_PROJECT_RUNTIME_LAUNCH_AGENTS_DIR:-${HOME_DIR}/Library/LaunchAgents}"
profile_slug="$(printf '%s' "${profile_id}" | tr -c 'A-Za-z0-9._-' '-')"
LABEL="${label_override:-${ACP_PROJECT_RUNTIME_LAUNCHD_LABEL:-ai.agent.project.${profile_slug}}}"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
WRAPPER_PATH="${WORKSPACE_DIR}/bin/agent-project-${profile_slug}-launchd.sh"

if [[ "${ACP_PROJECT_RUNTIME_SKIP_LAUNCHCTL:-0}" != "1" ]] && command -v launchctl >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
fi

rm -f "${PLIST_PATH}" "${WRAPPER_PATH}"

printf 'LAUNCHD_UNINSTALL_STATUS=ok\n'
printf 'PROFILE_ID=%s\n' "${profile_id}"
printf 'LABEL=%s\n' "${LABEL}"
printf 'PLIST=%s\n' "${PLIST_PATH}"
printf 'WRAPPER=%s\n' "${WRAPPER_PATH}"
