#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-dashboard-launchd.sh [--host 127.0.0.1] [--port 8765] [--label ai.agent.dashboard]

Installs a per-user LaunchAgent so the ACP worker dashboard starts automatically
after login/restart.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOME_DIR="${ACP_DASHBOARD_HOME_DIR:-${HOME:-}}"
SOURCE_HOME="${ACP_DASHBOARD_SOURCE_HOME:-$(cd "${FLOW_SKILL_DIR}/../../.." && pwd)}"
RUNTIME_HOME="${ACP_DASHBOARD_RUNTIME_HOME:-${HOME_DIR}/.agent-runtime/runtime-home}"
WORKSPACE_DIR="${ACP_DASHBOARD_WORKSPACE_DIR:-${HOME_DIR}/.agent-runtime/control-plane/workspace}"
PROFILE_REGISTRY_ROOT="${ACP_DASHBOARD_PROFILE_REGISTRY_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${HOME_DIR}/.agent-runtime/control-plane/profiles}}"
LAUNCH_AGENTS_DIR="${ACP_DASHBOARD_LAUNCH_AGENTS_DIR:-${HOME_DIR}/Library/LaunchAgents}"
LOG_DIR="${ACP_DASHBOARD_LOG_DIR:-${HOME_DIR}/.agent-runtime/logs}"
LABEL="${ACP_DASHBOARD_LABEL:-ai.agent.dashboard}"
HOST="${ACP_DASHBOARD_HOST:-127.0.0.1}"
PORT="${ACP_DASHBOARD_PORT:-8765}"
BASE_PATH="${ACP_DASHBOARD_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
SYNC_SCRIPT="${ACP_DASHBOARD_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/sync-shared-agent-home.sh}"
BOOTSTRAP_SCRIPT="${ACP_DASHBOARD_BOOTSTRAP_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/dashboard-launchd-bootstrap.sh}"
WRAPPER_PATH="${WORKSPACE_DIR}/bin/agent-dashboard-launchd.sh"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
STDOUT_LOG="${LOG_DIR}/agent-dashboard.stdout.log"
STDERR_LOG="${LOG_DIR}/agent-dashboard.stderr.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "${HOME_DIR}" ]]; then
  echo "install-dashboard-launchd requires HOME or ACP_DASHBOARD_HOME_DIR" >&2
  exit 64
fi

mkdir -p "${WORKSPACE_DIR}/bin" "${LAUNCH_AGENTS_DIR}" "${LOG_DIR}"

cat >"${WRAPPER_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ACP_DASHBOARD_HOME_DIR='${HOME_DIR}'
export ACP_DASHBOARD_SOURCE_HOME='${SOURCE_HOME}'
export ACP_DASHBOARD_RUNTIME_HOME='${RUNTIME_HOME}'
export ACP_DASHBOARD_PROFILE_REGISTRY_ROOT='${PROFILE_REGISTRY_ROOT}'
export ACP_DASHBOARD_HOST='${HOST}'
export ACP_DASHBOARD_PORT='${PORT}'
export ACP_DASHBOARD_PATH='${BASE_PATH}'
export ACP_DASHBOARD_SYNC_SCRIPT='${SYNC_SCRIPT}'
exec bash '${BOOTSTRAP_SCRIPT}'
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
		<key>PYTHONDONTWRITEBYTECODE</key>
		<string>1</string>
	</dict>
</dict>
</plist>
EOF

if [[ "${ACP_DASHBOARD_SKIP_LAUNCHCTL:-0}" == "1" ]]; then
  printf 'LAUNCHD_INSTALL_STATUS=skipped-launchctl\n'
  printf 'LABEL=%s\n' "${LABEL}"
  printf 'PLIST=%s\n' "${PLIST_PATH}"
  printf 'WRAPPER=%s\n' "${WRAPPER_PATH}"
  printf 'URL=http://%s:%s\n' "${HOST}" "${PORT}"
  exit 0
fi

user_domain="gui/$(id -u)"
launchctl bootout "${user_domain}/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "${user_domain}" "${PLIST_PATH}"
launchctl kickstart -k "${user_domain}/${LABEL}"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://${HOST}:${PORT}/api/snapshot.json" >/dev/null 2>&1; then
    printf 'LAUNCHD_INSTALL_STATUS=ok\n'
    printf 'LABEL=%s\n' "${LABEL}"
    printf 'PLIST=%s\n' "${PLIST_PATH}"
    printf 'WRAPPER=%s\n' "${WRAPPER_PATH}"
    printf 'URL=http://%s:%s\n' "${HOST}" "${PORT}"
    exit 0
  fi
  sleep 1
done

printf 'LAUNCHD_INSTALL_STATUS=unhealthy\n'
printf 'LABEL=%s\n' "${LABEL}"
printf 'PLIST=%s\n' "${PLIST_PATH}"
printf 'WRAPPER=%s\n' "${WRAPPER_PATH}"
printf 'URL=http://%s:%s\n' "${HOST}" "${PORT}"
exit 1
