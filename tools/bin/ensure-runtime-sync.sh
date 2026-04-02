#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ensure-runtime-sync.sh [--source-home <path>] [--runtime-home <path>] [--force] [--quiet]

Detect source/runtime drift for the published agent runtime and run
`sync-shared-agent-home.sh` only when needed.
EOF
}

source_home=""
runtime_home=""
force_sync="0"
quiet="0"

path_looks_like_skill_alias_root() {
  local candidate="${1:-}"
  local skill_name=""

  for skill_name in "$(flow_canonical_skill_name)" "$(flow_compat_skill_alias)"; do
    [[ -n "${skill_name}" ]] || continue
    [[ "${candidate}" == */skills/openclaw/"${skill_name}" ]] && return 0
  done

  return 1
}

read_stamped_source_home() {
  local stamp_path="${1:-}"
  local stamped=""

  [[ -f "${stamp_path}" ]] || return 0
  stamped="$(awk -F= '/^SOURCE_HOME=/{print $2; exit}' "${stamp_path}" 2>/dev/null | tr -d "[:space:]'\" " || true)"
  [[ -n "${stamped}" ]] || return 0
  printf '%s\n' "${stamped}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-home) source_home="${2:-}"; shift 2 ;;
    --runtime-home) runtime_home="${2:-}"; shift 2 ;;
    --force) force_sync="1"; shift ;;
    --quiet) quiet="1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
SYNC_SCRIPT="${ACP_RUNTIME_SYNC_SCRIPT:-${AGENT_CONTROL_PLANE_SYNC_SCRIPT:-${SCRIPT_DIR}/sync-shared-agent-home.sh}}"

if [[ -z "${runtime_home}" ]]; then
  runtime_home="${ACP_RUNTIME_SYNC_RUNTIME_HOME:-${AGENT_RUNTIME_HOME:-$(resolve_runtime_home)}}"
fi

runtime_home="$(mkdir -p "${runtime_home}" && cd "${runtime_home}" && pwd -P)"
stamp_file="${runtime_home}/.agent-control-plane-runtime-sync.env"

if [[ -z "${source_home}" ]]; then
  source_home="${ACP_RUNTIME_SYNC_SOURCE_HOME:-${AGENT_FLOW_SOURCE_HOME:-}}"
  if [[ -z "${source_home}" ]]; then
    if path_looks_like_skill_alias_root "${FLOW_SKILL_DIR}"; then
      source_home="$(read_stamped_source_home "${stamp_file}")"
      if [[ -z "${source_home}" ]]; then
        source_home="$(resolve_shared_agent_home "${FLOW_SKILL_DIR}")"
      fi
    else
      source_home="${FLOW_SKILL_DIR}"
    fi
  fi
fi

source_home="$(cd "${source_home}" && pwd -P)"

resolve_source_skill_dir() {
  local candidate=""
  local skill_name=""
  local root="${1:?source home required}"

  for skill_name in "$(flow_canonical_skill_name)" "$(flow_compat_skill_alias)"; do
    [[ -n "${skill_name}" ]] || continue
    candidate="${root}/skills/openclaw/${skill_name}"
    if flow_is_skill_root "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if flow_is_skill_root "${root}"; then
    printf '%s\n' "${root}"
    return 0
  fi

  return 1
}

compute_fingerprint() {
  python3 - "$@" <<'PY'
import hashlib
import os
import sys

h = hashlib.sha256()

for root in sys.argv[1:]:
    if not root or not os.path.isdir(root):
        continue
    root = os.path.realpath(root)
    h.update(root.encode("utf-8", "surrogateescape"))
    h.update(b"\0")
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d != ".git")
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            try:
                stat_result = os.stat(path)
            except OSError:
                continue
            relpath = os.path.relpath(path, root)
            h.update(relpath.encode("utf-8", "surrogateescape"))
            h.update(b"\0")
            h.update(str(stat_result.st_mtime_ns).encode("ascii"))
            h.update(b"\0")
            h.update(str(stat_result.st_size).encode("ascii"))
            h.update(b"\0")

print(h.hexdigest())
PY
}

source_skill_dir="$(resolve_source_skill_dir "${source_home}")"
source_tools_dir="${source_home}/tools"
source_quota_manager_dir="${source_home}/skills/openclaw/codex-quota-manager"
runtime_skill_dir="${runtime_home}/skills/openclaw/$(flow_canonical_skill_name)"

source_fingerprint="$(
  compute_fingerprint \
    "${source_tools_dir}" \
    "${source_quota_manager_dir}" \
    "${source_skill_dir}"
)"

existing_fingerprint=""
if [[ -f "${stamp_file}" ]]; then
  existing_fingerprint="$(awk -F= '/^SOURCE_FINGERPRINT=/{print $2}' "${stamp_file}" 2>/dev/null | tr -d "[:space:]'\"" || true)"
fi

sync_status="unchanged"
if [[ "${force_sync}" == "1" || ! -d "${runtime_skill_dir}" || "${existing_fingerprint}" != "${source_fingerprint}" ]]; then
  bash "${SYNC_SCRIPT}" "${source_home}" "${runtime_home}" >/dev/null
  sync_status="updated"
fi

updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
tmp_file="${stamp_file}.tmp.$$"
{
  printf 'SOURCE_HOME=%q\n' "${source_home}"
  printf 'SOURCE_SKILL_DIR=%q\n' "${source_skill_dir}"
  printf 'RUNTIME_HOME=%q\n' "${runtime_home}"
  printf 'RUNTIME_SKILL_DIR=%q\n' "${runtime_skill_dir}"
  printf 'SOURCE_FINGERPRINT=%q\n' "${source_fingerprint}"
  printf 'SYNC_STATUS=%q\n' "${sync_status}"
  printf 'UPDATED_AT=%q\n' "${updated_at}"
} >"${tmp_file}"
mv "${tmp_file}" "${stamp_file}"

if [[ "${quiet}" != "1" ]]; then
  printf 'SYNC_STATUS=%s\n' "${sync_status}"
  printf 'SOURCE_HOME=%s\n' "${source_home}"
  printf 'SOURCE_SKILL_DIR=%s\n' "${source_skill_dir}"
  printf 'RUNTIME_HOME=%s\n' "${runtime_home}"
  printf 'RUNTIME_SKILL_DIR=%s\n' "${runtime_skill_dir}"
  printf 'SOURCE_FINGERPRINT=%s\n' "${source_fingerprint}"
  printf 'STAMP_FILE=%s\n' "${stamp_file}"
fi
