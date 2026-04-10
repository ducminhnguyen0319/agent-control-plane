#!/usr/bin/env bash
# reconcile-bootstrap-lib.sh — shared bootstrap helpers for reconcile scripts.
# Sourced by both agent-project-reconcile-pr-session and
# agent-project-reconcile-issue-session to avoid duplicating the bootstrap
# preamble.

bootstrap_flow_shell_lib() {
  local candidate=""
  local skill_name=""

  for candidate in \
    "${SCRIPT_DIR}/flow-shell-lib.sh" \
    "${AGENT_CONTROL_PLANE_ROOT:-}/tools/bin/flow-shell-lib.sh" \
    "${ACP_ROOT:-}/tools/bin/flow-shell-lib.sh" \
    "${F_LOSNING_FLOW_ROOT:-}/tools/bin/flow-shell-lib.sh" \
    "${AGENT_FLOW_SKILL_ROOT:-}/tools/bin/flow-shell-lib.sh" \
    "${SHARED_AGENT_HOME:-}/tools/bin/flow-shell-lib.sh" \
    "$(pwd)/tools/bin/flow-shell-lib.sh"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if [[ -n "${SHARED_AGENT_HOME:-}" ]]; then
    for skill_name in "${AGENT_CONTROL_PLANE_SKILL_NAME:-agent-control-plane}" "${AGENT_CONTROL_PLANE_COMPAT_ALIAS:-}"; do
      [[ -n "${skill_name}" ]] || continue
      candidate="${SHARED_AGENT_HOME}/skills/openclaw/${skill_name}/tools/bin/flow-shell-lib.sh"
      if [[ -f "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
  fi

  echo "unable to locate flow-shell-lib.sh for reconcile bootstrap" >&2
  return 1
}

FLOW_SHELL_LIB_PATH="$(bootstrap_flow_shell_lib)"
BOOTSTRAP_TOOLS_DIR="$(cd "$(dirname "${FLOW_SHELL_LIB_PATH}")" && pwd)"
# shellcheck source=/dev/null
source "${FLOW_SHELL_LIB_PATH}"

resolve_reconcile_tools_dir() {
  local candidate_root=""
  local skill_name=""

  for candidate_root in \
    "${AGENT_CONTROL_PLANE_ROOT:-}" \
    "${ACP_ROOT:-}" \
    "${F_LOSNING_FLOW_ROOT:-}" \
    "${AGENT_FLOW_SKILL_ROOT:-}"; do
    if [[ -n "${candidate_root}" && -d "${candidate_root}/tools/bin" ]]; then
      printf '%s/tools/bin\n' "${candidate_root}"
      return 0
    fi
  done

  if [[ -n "${SHARED_AGENT_HOME:-}" ]]; then
    if [[ -d "${SHARED_AGENT_HOME}/tools/bin" ]]; then
      printf '%s/tools/bin\n' "${SHARED_AGENT_HOME}"
      return 0
    fi
    for skill_name in "${AGENT_CONTROL_PLANE_SKILL_NAME:-agent-control-plane}" "${AGENT_CONTROL_PLANE_COMPAT_ALIAS:-}"; do
      [[ -n "${skill_name}" ]] || continue
      candidate_root="${SHARED_AGENT_HOME}/skills/openclaw/${skill_name}"
      if [[ -d "${candidate_root}/tools/bin" ]]; then
        printf '%s/tools/bin\n' "${candidate_root}"
        return 0
      fi
    done
  fi

  if [[ -d "${SCRIPT_DIR}" ]]; then
    printf '%s\n' "${SCRIPT_DIR}"
    return 0
  fi

  printf '%s\n' "${BOOTSTRAP_TOOLS_DIR}"
}

shared_tools_dir="$(resolve_reconcile_tools_dir)"
resolve_reconcile_helper_path() {
  local helper_name="${1:?helper name required}"
  local candidate=""

  for candidate in \
    "${SCRIPT_DIR}/${helper_name}" \
    "${BOOTSTRAP_TOOLS_DIR}/${helper_name}" \
    "${shared_tools_dir}/${helper_name}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  echo "unable to locate ${helper_name} for reconcile bootstrap" >&2
  return 1
}

FLOW_CONFIG_LIB_PATH="$(resolve_reconcile_helper_path "flow-config-lib.sh")"
# shellcheck source=/dev/null
source "${FLOW_CONFIG_LIB_PATH}"

require_transition() {
  local step="${1:?step required}"
  shift
  if ! "$@"; then
    echo "reconcile transition failed: ${step}" >&2
    exit 1
  fi
}
