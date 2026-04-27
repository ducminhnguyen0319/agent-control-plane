#!/usr/bin/env bash
# adapter-interface.sh
# Standard interface for ACP backend adapters
# All adapters must implement these functions:
#
#   adapter_info()        - Print adapter metadata (id, name, type, version)
#   adapter_health_check() - Check if backend is available (exit 0 = healthy)
#   adapter_run()          - Execute a task (params: MODE SESSION WORKTREE PROMPT_FILE)
#   adapter_status()       - Get run status (params: RUNS_ROOT SESSION)
#
# Usage: source this file in adapter implementations

set -euo pipefail

# Default adapter metadata (override in adapter script)
ADAPTER_ID="${ADAPTER_ID:-unknown}"
ADAPTER_NAME="${ADAPTER_NAME:-Unknown Adapter}"
ADAPTER_TYPE="${ADAPTER_TYPE:-unknown}"  # coding, local-model, cloud-api
ADAPTER_VERSION="${ADAPTER_VERSION:-0.0.1}"

# Print adapter metadata as key=value pairs
adapter_info() {
  cat <<EOF
id=${ADAPTER_ID}
name=${ADAPTER_NAME}
type=${ADAPTER_TYPE}
version=${ADAPTER_VERSION}
model=${ADAPTER_MODEL:-}
base_url=${ADAPTER_BASE_URL:-}
EOF
}

# Default health check (override in adapter)
# Returns: 0 = healthy, 1 = unhealthy
adapter_health_check() {
  echo "WARN: adapter_health_check() not implemented for ${ADAPTER_ID}"
  return 0
}

# Default run function (MUST override in adapter)
adapter_run() {
  echo "ERROR: adapter_run() not implemented for ${ADAPTER_ID}"
  return 1
}

# Default status function (override in adapter if needed)
adapter_status() {
  local runs_root="${1:?usage: adapter_status RUNS_ROOT SESSION}"
  local session="${2:?usage: adapter_status RUNS_ROOT SESSION}"
  local run_dir="${runs_root}/${session}"
  
  if [[ ! -d "$run_dir" ]]; then
    echo "NOT_FOUND"
    return 1
  fi
  
  if [[ -f "$run_dir/result.env" ]]; then
    source "$run_dir/result.env"
    echo "${OUTCOME:-UNKNOWN}"
    return 0
  fi
  
  if [[ -f "$run_dir/runner.env" ]]; then
    source "$run_dir/runner.env"
    echo "${RUNNER_STATE:-RUNNING}"
    return 0
  fi
  
  echo "RUNNING"
  return 0
}

# Load adapter implementation
# Usage: adapter_load IMPLEMENTATION_SCRIPT
adapter_load() {
  local impl="${1:?usage: adapter_load IMPLEMENTATION_SCRIPT}"
  if [[ ! -f "$impl" ]]; then
    echo "ERROR: Adapter implementation not found: $impl"
    return 1
  fi
  source "$impl"
}

# Run a command with a wall-clock timeout. Uses GNU `timeout` / `gtimeout`
# when available, else falls back to a python3 wrapper, else perl. Streams
# the child's stdout/stderr to the caller. Exits 124 on timeout.
# Usage: adapter_run_with_timeout SECS CMD [ARGS...]
adapter_run_with_timeout() {
  local secs="${1:?usage: adapter_run_with_timeout SECS CMD [ARGS...]}"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${secs}" "$@"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "${secs}" "$@"
    return $?
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${secs}" "$@" <<'PY'
import subprocess, sys
secs = float(sys.argv[1])
cmd = sys.argv[2:]
try:
    proc = subprocess.Popen(cmd)
except FileNotFoundError as exc:
    sys.stderr.write("adapter_run_with_timeout: %s\n" % exc)
    sys.exit(127)
try:
    proc.wait(timeout=secs)
except subprocess.TimeoutExpired:
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    sys.exit(124)
sys.exit(proc.returncode)
PY
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e '
my $secs = shift @ARGV;
my $pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) { exec { $ARGV[0] } @ARGV or exit 127; }
local $SIG{ALRM} = sub { kill "TERM", $pid; sleep 10; kill "KILL", $pid; waitpid($pid, 0); exit 124; };
alarm $secs;
waitpid($pid, 0);
alarm 0;
my $rc = $? >> 8;
exit $rc;
' "${secs}" "$@"
    return $?
  fi
  echo "adapter_run_with_timeout: no gtimeout/timeout/python3/perl available; running without timeout" >&2
  "$@"
}

# Validate adapter implements required functions
adapter_validate() {
  local missing=()
  type adapter_info >/dev/null 2>&1 || missing+=("adapter_info")
  type adapter_health_check >/dev/null 2>&1 || missing+=("adapter_health_check")
  type adapter_run >/dev/null 2>&1 || missing+=("adapter_run")
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Adapter ${ADAPTER_ID} missing required functions: ${missing[*]}"
    return 1
  fi
  
  return 0
}
