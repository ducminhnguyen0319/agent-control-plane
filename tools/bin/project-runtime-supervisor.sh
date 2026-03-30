#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  project-runtime-supervisor.sh --bootstrap-script <path> --pid-file <path> [--delay-seconds <n>] [--interval-seconds <n>]

Keep invoking a project bootstrap script in a long-lived loop and expose the
supervisor pid through a pid file for `project-runtimectl`.
EOF
}

bootstrap_script=""
pid_file=""
delay_seconds="0"
interval_seconds="15"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-script) bootstrap_script="${2:-}"; shift 2 ;;
    --pid-file) pid_file="${2:-}"; shift 2 ;;
    --delay-seconds) delay_seconds="${2:-}"; shift 2 ;;
    --interval-seconds) interval_seconds="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "${bootstrap_script}" || -z "${pid_file}" ]]; then
  usage >&2
  exit 64
fi

case "${delay_seconds}" in
  ''|*[!0-9]*) echo "--delay-seconds must be numeric" >&2; exit 64 ;;
esac

case "${interval_seconds}" in
  ''|*[!0-9]*) echo "--interval-seconds must be numeric" >&2; exit 64 ;;
esac

mkdir -p "$(dirname "${pid_file}")"
printf '%s\n' "$$" >"${pid_file}"
trap 'rm -f "${pid_file}"' EXIT
trap '' HUP

first_pass="1"
while true; do
  if [[ "${first_pass}" == "1" && "${delay_seconds}" != "0" ]]; then
    sleep "${delay_seconds}"
  fi
  first_pass="0"
  "${bootstrap_script}" >/dev/null 2>&1 || true
  sleep "${interval_seconds}"
done
