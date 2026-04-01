#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  provider-cooldown-state.sh [backend] [model] get|schedule|clear [reason]

Examples:
  provider-cooldown-state.sh get
  provider-cooldown-state.sh openclaw openrouter/qwen/qwen3.6-plus-preview:free schedule provider-quota-limit
EOF
}

backend=""
model=""
action=""
reason=""

case "$#" in
  1)
    action="${1:-}"
    ;;
  2)
    action="${1:-}"
    reason="${2:-}"
    ;;
  3)
    backend="${1:-}"
    model="${2:-}"
    action="${3:-}"
    ;;
  4)
    backend="${1:-}"
    model="${2:-}"
    action="${3:-}"
    reason="${4:-}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
COOLDOWNS="$(flow_resolve_provider_quota_cooldowns "${CONFIG_YAML}")"

resolve_backend() {
  local raw_backend="${1:-}"

  if [[ -n "${raw_backend}" ]]; then
    printf '%s\n' "${raw_backend}"
    return 0
  fi

  if [[ -n "${CODING_WORKER:-}" ]]; then
    printf '%s\n' "${CODING_WORKER}"
    return 0
  fi

  if [[ -n "${ACP_ACTIVE_PROVIDER_BACKEND:-${F_LOSNING_ACTIVE_PROVIDER_BACKEND:-}}" ]]; then
    printf '%s\n' "${ACP_ACTIVE_PROVIDER_BACKEND:-${F_LOSNING_ACTIVE_PROVIDER_BACKEND:-}}"
    return 0
  fi

  if [[ -n "${ACP_CODING_WORKER:-${F_LOSNING_CODING_WORKER:-}}" ]]; then
    printf '%s\n' "${ACP_CODING_WORKER:-${F_LOSNING_CODING_WORKER:-}}"
    return 0
  fi

  flow_config_get "${CONFIG_YAML}" "execution.coding_worker"
}

resolve_model() {
  local resolved_backend="${1:?backend required}"
  local raw_model="${2:-}"
  local active_provider_model="${ACP_ACTIVE_PROVIDER_MODEL:-${F_LOSNING_ACTIVE_PROVIDER_MODEL:-}}"

  if [[ -n "${raw_model}" ]]; then
    printf '%s\n' "${raw_model}"
    return 0
  fi

  case "${resolved_backend}" in
    openclaw)
      if [[ -n "${OPENCLAW_MODEL:-}" ]]; then
        printf '%s\n' "${OPENCLAW_MODEL}"
      elif [[ -n "${active_provider_model}" ]]; then
        printf '%s\n' "${active_provider_model}"
      elif [[ -n "${ACP_OPENCLAW_MODEL:-${F_LOSNING_OPENCLAW_MODEL:-}}" ]]; then
        printf '%s\n' "${ACP_OPENCLAW_MODEL:-${F_LOSNING_OPENCLAW_MODEL:-}}"
      else
        flow_config_get "${CONFIG_YAML}" "execution.openclaw.model"
      fi
      ;;
    claude)
      if [[ -n "${CLAUDE_MODEL:-}" ]]; then
        printf '%s\n' "${CLAUDE_MODEL}"
      elif [[ -n "${active_provider_model}" ]]; then
        printf '%s\n' "${active_provider_model}"
      elif [[ -n "${ACP_CLAUDE_MODEL:-${F_LOSNING_CLAUDE_MODEL:-}}" ]]; then
        printf '%s\n' "${ACP_CLAUDE_MODEL:-${F_LOSNING_CLAUDE_MODEL:-}}"
      else
        flow_config_get "${CONFIG_YAML}" "execution.claude.model"
      fi
      ;;
    codex)
      if [[ -n "${CODEX_PROFILE_SAFE:-}" ]]; then
        printf '%s\n' "${CODEX_PROFILE_SAFE}"
      elif [[ -n "${active_provider_model}" ]]; then
        printf '%s\n' "${active_provider_model}"
      elif [[ -n "${ACP_CODEX_PROFILE_SAFE:-${F_LOSNING_CODEX_PROFILE_SAFE:-}}" ]]; then
        printf '%s\n' "${ACP_CODEX_PROFILE_SAFE:-${F_LOSNING_CODEX_PROFILE_SAFE:-}}"
      else
        flow_config_get "${CONFIG_YAML}" "execution.safe_profile"
      fi
      ;;
    *)
      printf '\n'
      ;;
  esac
}

backend="$(resolve_backend "${backend}")"
if [[ -z "${backend}" ]]; then
  echo "provider backend is required" >&2
  exit 1
fi

model="$(resolve_model "${backend}" "${model}")"
if [[ -z "${model}" ]]; then
  echo "provider model/profile is required for backend ${backend}" >&2
  exit 1
fi

case "${action}" in
  get|schedule|clear) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

provider_key="$(flow_sanitize_provider_key "${backend}-${model}")"
out="$(
  ACP_STATE_ROOT="${STATE_ROOT}" \
  ACP_PROVIDER_QUOTA_COOLDOWNS="${COOLDOWNS}" \
  bash "${SCRIPT_DIR}/agent-project-retry-state" \
    --state-root "${STATE_ROOT}" \
    --kind provider \
    --item-id "${provider_key}" \
    --action "${action}" \
    --reason "${reason}" \
    --cooldowns "${COOLDOWNS}"
)"

printf 'BACKEND=%s\n' "${backend}"
printf 'MODEL=%s\n' "${model}"
printf 'PROVIDER_KEY=%s\n' "${provider_key}"
printf '%s\n' "${out}"
