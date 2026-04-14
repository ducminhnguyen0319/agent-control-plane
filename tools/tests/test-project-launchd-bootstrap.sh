#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_BIN="${FLOW_ROOT}/tools/bin/project-launchd-bootstrap.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
runtime_home="$tmpdir/runtime-home"
runtime_bootstrap_bin="$runtime_home/skills/openclaw/agent-control-plane/tools/bin/project-launchd-bootstrap.sh"
profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
capture_dir="$tmpdir/capture"
sync_script="$tmpdir/sync.sh"
ensure_sync_script="$tmpdir/ensure-sync.sh"
runtime_heartbeat_script="$runtime_home/skills/openclaw/agent-control-plane/tools/bin/heartbeat-safe-auto.sh"
env_override_heartbeat_script="$tmpdir/env-override-heartbeat.sh"
env_file="$profile_dir/runtime.env"

mkdir -p "$home_dir" "$profile_dir" "$(dirname "$runtime_heartbeat_script")" "$capture_dir"
cp "$BOOTSTRAP_BIN" "$runtime_bootstrap_bin"
chmod +x "$runtime_bootstrap_bin"

cat >"$sync_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'SYNC_SOURCE=%s\n' "$1" >"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/sync.log"
printf 'SYNC_TARGET=%s\n' "$2" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/sync.log"
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
printf 'ENSURE_ARGS=%s\n' "${args}" >"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/ensure.log"
[[ -n "${source_value}" ]] && printf 'ENSURE_SOURCE=%s\n' "${source_value}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/ensure.log"
printf 'ENSURE_TARGET=%s\n' "${target_value}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/ensure.log"
EOF
chmod +x "$ensure_sync_script"

cat >"$runtime_heartbeat_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'PROFILE_ID=%s\n' "${ACP_PROJECT_ID:-}" >"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "${ACP_PROFILE_REGISTRY_ROOT:-}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
printf 'HOME=%s\n' "${HOME:-}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
printf 'PATH=%s\n' "${PATH:-}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  printf 'HAS_OPENROUTER_API_KEY=yes\n' >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
else
  printf 'HAS_OPENROUTER_API_KEY=no\n' >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
fi
EOF
chmod +x "$runtime_heartbeat_script"

cat >"$env_file" <<'EOF'
OPENROUTER_API_KEY=test-openrouter-key
EOF

cat >"$env_override_heartbeat_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'HEARTBEAT_SOURCE=env-file\n' >"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
printf 'PROFILE_ID=%s\n' "${ACP_PROJECT_ID:-}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
printf 'PATH=%s\n' "${PATH:-}" >>"${ACP_PROJECT_RUNTIME_CAPTURE_DIR}/heartbeat.log"
EOF
chmod +x "$env_override_heartbeat_script"

ACP_PROJECT_RUNTIME_HOME_DIR="$home_dir" \
ACP_PROJECT_RUNTIME_SOURCE_HOME="$tmpdir/source-home" \
ACP_PROJECT_RUNTIME_RUNTIME_HOME="$runtime_home" \
ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROJECT_RUNTIME_PROFILE_ID="demo" \
ACP_PROJECT_RUNTIME_SYNC_SCRIPT="$sync_script" \
ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT="$ensure_sync_script" \
ACP_PROJECT_RUNTIME_HEARTBEAT_SCRIPT="$runtime_heartbeat_script" \
ACP_PROJECT_RUNTIME_CAPTURE_DIR="$capture_dir" \
bash "$BOOTSTRAP_BIN"

grep -q '^ENSURE_ARGS=--source-home '"$tmpdir"'/source-home --runtime-home '"$runtime_home"' --quiet$' "$capture_dir/ensure.log"
grep -q "^ENSURE_SOURCE=$tmpdir/source-home$" "$capture_dir/ensure.log"
grep -q "^ENSURE_TARGET=$runtime_home$" "$capture_dir/ensure.log"
grep -q '^PROFILE_ID=demo$' "$capture_dir/heartbeat.log"
grep -q "^PROFILE_REGISTRY_ROOT=$profile_registry_root$" "$capture_dir/heartbeat.log"
grep -q "^HOME=$home_dir$" "$capture_dir/heartbeat.log"
grep -q '^HAS_OPENROUTER_API_KEY=yes$' "$capture_dir/heartbeat.log"

rm -f "$capture_dir/ensure.log" "$capture_dir/heartbeat.log"

ACP_PROJECT_RUNTIME_HOME_DIR="$home_dir" \
ACP_PROJECT_RUNTIME_RUNTIME_HOME="$runtime_home" \
ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROJECT_RUNTIME_PROFILE_ID="demo" \
ACP_PROJECT_RUNTIME_SYNC_SCRIPT="$sync_script" \
ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT="$ensure_sync_script" \
ACP_PROJECT_RUNTIME_HEARTBEAT_SCRIPT="$runtime_heartbeat_script" \
ACP_PROJECT_RUNTIME_CAPTURE_DIR="$capture_dir" \
bash "$BOOTSTRAP_BIN"

grep -q '^ENSURE_ARGS=--runtime-home '"$runtime_home"' --quiet$' "$capture_dir/ensure.log"
if grep -q '^ENSURE_SOURCE=' "$capture_dir/ensure.log"; then
  echo "bootstrap passed unexpected source-home override" >&2
  exit 1
fi

cat >"$env_file" <<EOF
OPENROUTER_API_KEY=test-openrouter-key
ACP_PROJECT_RUNTIME_HEARTBEAT_SCRIPT=$env_override_heartbeat_script
ACP_PROJECT_RUNTIME_PATH=/custom/bin:/usr/bin:/bin
ACP_PROJECT_RUNTIME_ALWAYS_SYNC=1
EOF

rm -f "$capture_dir/ensure.log" "$capture_dir/heartbeat.log"

ACP_PROJECT_RUNTIME_HOME_DIR="$home_dir" \
ACP_PROJECT_RUNTIME_SOURCE_HOME="$tmpdir/source-home" \
ACP_PROJECT_RUNTIME_RUNTIME_HOME="$runtime_home" \
ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROJECT_RUNTIME_PROFILE_ID="demo" \
ACP_PROJECT_RUNTIME_SYNC_SCRIPT="$sync_script" \
ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT="$ensure_sync_script" \
ACP_PROJECT_RUNTIME_CAPTURE_DIR="$capture_dir" \
bash "$BOOTSTRAP_BIN"

grep -q '^ENSURE_ARGS=--force --source-home '"$tmpdir"'/source-home --runtime-home '"$runtime_home"' --quiet$' "$capture_dir/ensure.log"
grep -q '^HEARTBEAT_SOURCE=env-file$' "$capture_dir/heartbeat.log"
grep -q '^PROFILE_ID=demo$' "$capture_dir/heartbeat.log"
grep -q '^PATH=/custom/bin:/usr/bin:/bin$' "$capture_dir/heartbeat.log"

rm -f "$capture_dir/ensure.log" "$capture_dir/heartbeat.log"

ACP_PROJECT_RUNTIME_HOME_DIR="$home_dir" \
ACP_PROJECT_RUNTIME_RUNTIME_HOME="$runtime_home" \
ACP_PROJECT_RUNTIME_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
ACP_PROJECT_RUNTIME_PROFILE_ID="demo" \
ACP_PROJECT_RUNTIME_SYNC_SCRIPT="$sync_script" \
ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT="$ensure_sync_script" \
ACP_PROJECT_RUNTIME_CAPTURE_DIR="$capture_dir" \
bash "$runtime_bootstrap_bin"

if [[ -f "$capture_dir/ensure.log" ]]; then
  echo "runtime-home bootstrap unexpectedly attempted ensure-runtime-sync" >&2
  exit 1
fi
grep -q '^HEARTBEAT_SOURCE=env-file$' "$capture_dir/heartbeat.log"

echo "project launchd bootstrap test passed"
