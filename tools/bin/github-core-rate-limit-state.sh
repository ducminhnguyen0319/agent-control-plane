#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  github-core-rate-limit-state.sh get
  github-core-rate-limit-state.sh schedule [reason] [--next-at-epoch <unix-seconds>]
  github-core-rate-limit-state.sh clear
EOF
}

action="${1:-}"
reason="${2:-github-api-rate-limit}"
next_at_epoch=""

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

shift || true
if [[ $# -gt 0 ]]; then
  reason="${1:-github-api-rate-limit}"
  shift || true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --next-at-epoch)
      next_at_epoch="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${action}" in
  get|schedule|clear) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
COOLDOWNS="$(flow_resolve_retry_cooldowns "${CONFIG_YAML}")"

exec_args=(
  --state-root "${STATE_ROOT}"
  --kind github
  --item-id core-api
  --action "${action}"
  --reason "${reason}"
  --cooldowns "${COOLDOWNS}"
)

if [[ "${action}" == "schedule" && "${next_at_epoch}" =~ ^[0-9]+$ ]]; then
  exec_args+=(--next-at-epoch "${next_at_epoch}")
fi

ACP_STATE_ROOT="${STATE_ROOT}" \
ACP_RETRY_COOLDOWNS="${COOLDOWNS}" \
exec bash "${SCRIPT_DIR}/agent-project-retry-state" "${exec_args[@]}"
