#!/usr/bin/env bash
# adapter-capabilities.sh
# Standardized capability reporting for all ACP backend adapters
# Source this after adapter-interface.sh

set -euo pipefail

# Default capabilities (override in adapter)
ADAPTER_CAP_CONTEXT_WINDOW=0
ADAPTER_CAP_STREAMING=false
ADAPTER_CAP_TOOLS_SUPPORT=false
ADAPTER_CAP_LOCAL_MODEL=false
ADAPTER_CAP_CLOUD_API=false
ADAPTER_CAP_RESIDENT_MODE=false
ADAPTER_CAP_JSON_OUTPUT=false
ADAPTER_CAP_MAX_TIMEOUT=3600

# Print adapter capabilities as key=value pairs
adapter_capabilities() {
  cat <<EOF
id=${ADAPTER_ID}
name=${ADAPTER_NAME}
type=${ADAPTER_TYPE}
version=${ADAPTER_VERSION}
model=${ADAPTER_MODEL:-}
base_url=${ADAPTER_BASE_URL:-}
context_window=${ADAPTER_CAP_CONTEXT_WINDOW}
streaming=${ADAPTER_CAP_STREAMING}
tools_support=${ADAPTER_CAP_TOOLS_SUPPORT}
local_model=${ADAPTER_CAP_LOCAL_MODEL}
cloud_api=${ADAPTER_CAP_CLOUD_API}
resident_mode=${ADAPTER_CAP_RESIDENT_MODE}
json_output=${ADAPTER_CAP_JSON_OUTPUT}
max_timeout=${ADAPTER_CAP_MAX_TIMEOUT}
EOF
}

# Check if adapter supports a specific capability
# Usage: adapter_supports CAPABILITY_NAME
adapter_supports() {
  local cap="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  local value
  case "$cap" in
    STREAMING) value="${ADAPTER_CAP_STREAMING}" ;;
    TOOLS) value="${ADAPTER_CAP_TOOLS_SUPPORT}" ;;
    LOCAL) value="${ADAPTER_CAP_LOCAL_MODEL}" ;;
    CLOUD) value="${ADAPTER_CAP_CLOUD_API}" ;;
    RESIDENT) value="${ADAPTER_CAP_RESIDENT_MODE}" ;;
    JSON) value="${ADAPTER_CAP_JSON_OUTPUT}" ;;
    *) 
      echo "UNKNOWN_CAPABILITY: $1"
      return 1
      ;;
  esac
  [[ "$value" == "true" ]] && return 0
  return 1
}

# Validate adapter implements required functions
adapter_validate_interface() {
  local errors=0
  for func in adapter_info adapter_health_check adapter_run adapter_status; do
    if ! declare -f "$func" >/dev/null 2>&1; then
      echo "ERROR: $func() not implemented in ${ADAPTER_ID} adapter"
      errors=$((errors + 1))
    fi
  done
  [[ $errors -eq 0 ]] && return 0
  return 1
}

# Enhanced health check that also reports capabilities
adapter_health_check_with_capabilities() {
  local health_output
  if ! health_output="$(adapter_health_check 2>&1)"; then
    echo "UNHEALTHY"
    echo "$health_output"
    return 1
  fi
  echo "HEALTHY"
  echo "$health_output"
  adapter_capabilities
  return 0
}
