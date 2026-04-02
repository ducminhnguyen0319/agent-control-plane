#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_BIN="${FLOW_ROOT}/tools/bin/dashboard-launchd-bootstrap.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
runtime_home="$tmpdir/runtime-home"
profile_registry_root="$tmpdir/profiles"
capture_dir="$tmpdir/capture"
sync_script="$tmpdir/sync.sh"
ensure_sync_script="$tmpdir/ensure-sync.sh"
runtime_serve_script="$runtime_home/skills/openclaw/agent-control-plane/tools/bin/serve-dashboard.sh"

mkdir -p "$home_dir" "$profile_registry_root" "$(dirname "$runtime_serve_script")" "$capture_dir"

cat >"$sync_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'SYNC_SOURCE=%s\n' "$1" >"${ACP_DASHBOARD_CAPTURE_DIR}/sync.log"
printf 'SYNC_TARGET=%s\n' "$2" >>"${ACP_DASHBOARD_CAPTURE_DIR}/sync.log"
EOF
chmod +x "$sync_script"

cat >"$ensure_sync_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
source_value=""
target_value=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-home) source_value="${2:-}"; shift 2 ;;
    --runtime-home) target_value="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'ENSURE_ARGS=%s\n' "${args}" >"${ACP_DASHBOARD_CAPTURE_DIR}/ensure.log"
[[ -n "${source_value}" ]] && printf 'ENSURE_SOURCE=%s\n' "${source_value}" >>"${ACP_DASHBOARD_CAPTURE_DIR}/ensure.log"
printf 'ENSURE_TARGET=%s\n' "${target_value}" >>"${ACP_DASHBOARD_CAPTURE_DIR}/ensure.log"
EOF
chmod +x "$ensure_sync_script"

cat >"$runtime_serve_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGS=%s %s %s %s\n' "$1" "$2" "$3" "$4" >"${ACP_DASHBOARD_CAPTURE_DIR}/serve.log"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "${ACP_PROFILE_REGISTRY_ROOT:-}" >>"${ACP_DASHBOARD_CAPTURE_DIR}/serve.log"
printf 'HOME=%s\n' "${HOME:-}" >>"${ACP_DASHBOARD_CAPTURE_DIR}/serve.log"
printf 'PYTHONDONTWRITEBYTECODE=%s\n' "${PYTHONDONTWRITEBYTECODE:-}" >>"${ACP_DASHBOARD_CAPTURE_DIR}/serve.log"
EOF
chmod +x "$runtime_serve_script"

ACP_DASHBOARD_HOME_DIR="$home_dir" \
ACP_DASHBOARD_SOURCE_HOME="$tmpdir/source-home" \
ACP_DASHBOARD_RUNTIME_HOME="$runtime_home" \
ACP_DASHBOARD_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_DASHBOARD_HOST="127.0.0.1" \
ACP_DASHBOARD_PORT="9911" \
ACP_DASHBOARD_SYNC_SCRIPT="$sync_script" \
ACP_DASHBOARD_ENSURE_SYNC_SCRIPT="$ensure_sync_script" \
ACP_DASHBOARD_RUNTIME_SERVE_SCRIPT="$runtime_serve_script" \
ACP_DASHBOARD_CAPTURE_DIR="$capture_dir" \
bash "$BOOTSTRAP_BIN"

grep -q '^ENSURE_ARGS=--source-home '"$tmpdir"'/source-home --runtime-home '"$runtime_home"' --quiet$' "$capture_dir/ensure.log"
grep -q "^ENSURE_SOURCE=$tmpdir/source-home$" "$capture_dir/ensure.log"
grep -q "^ENSURE_TARGET=$runtime_home$" "$capture_dir/ensure.log"
grep -q '^ARGS=--host 127.0.0.1 --port 9911$' "$capture_dir/serve.log"
grep -q "^PROFILE_REGISTRY_ROOT=$profile_registry_root$" "$capture_dir/serve.log"
grep -q "^HOME=$home_dir$" "$capture_dir/serve.log"
grep -q '^PYTHONDONTWRITEBYTECODE=1$' "$capture_dir/serve.log"

rm -f "$capture_dir/ensure.log" "$capture_dir/serve.log"

ACP_DASHBOARD_HOME_DIR="$home_dir" \
ACP_DASHBOARD_RUNTIME_HOME="$runtime_home" \
ACP_DASHBOARD_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_DASHBOARD_HOST="127.0.0.1" \
ACP_DASHBOARD_PORT="9911" \
ACP_DASHBOARD_SYNC_SCRIPT="$sync_script" \
ACP_DASHBOARD_ENSURE_SYNC_SCRIPT="$ensure_sync_script" \
ACP_DASHBOARD_RUNTIME_SERVE_SCRIPT="$runtime_serve_script" \
ACP_DASHBOARD_CAPTURE_DIR="$capture_dir" \
bash "$BOOTSTRAP_BIN"

grep -q '^ENSURE_ARGS=--runtime-home '"$runtime_home"' --quiet$' "$capture_dir/ensure.log"
if grep -q '^ENSURE_SOURCE=' "$capture_dir/ensure.log"; then
  echo "dashboard bootstrap passed unexpected source-home override" >&2
  exit 1
fi

echo "dashboard launchd bootstrap test passed"
