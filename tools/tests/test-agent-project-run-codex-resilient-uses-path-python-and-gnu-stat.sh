#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-portable-python-stat.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

real_python="$(command -v python3 2>/dev/null || command -v python)"
bin_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
worktree="$tmpdir/worktree"
host_run_dir="$tmpdir/run"
sandbox_run_dir="$tmpdir/sandbox"
prompt_file="$tmpdir/prompt.md"
output_file="$host_run_dir/run.log"
runner_env="$host_run_dir/runner.env"
python_capture="$tmpdir/python.log"

mkdir -p "$bin_dir" "$home_dir/.codex" "$worktree" "$host_run_dir" "$sandbox_run_dir"

cat >"$bin_dir/python3" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$python_capture"
exec "$real_python" "\$@"
EOF

cat >"$bin_dir/stat" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" != "-c" ]]; then
  echo "unsupported stat args: \$*" >&2
  exit 64
fi

format="\${2:-}"
path="\${3:-}"

case "\$format" in
  %s)
    exec "$real_python" - "\$path" <<'PY'
import os
import sys

print(os.path.getsize(sys.argv[1]))
PY
    ;;
  %Y)
    exec "$real_python" - "\$path" <<'PY'
import os
import sys

print(int(os.path.getmtime(sys.argv[1])))
PY
    ;;
  *)
    echo "unsupported stat format: \$format" >&2
    exit 64
    ;;
esac
EOF

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  printf 'Logged in using ChatGPT\n'
  exit 0
fi

if [[ "${1:-}" == "exec" ]]; then
  printf '{"type":"thread.started","thread_id":"thread-portable-stat"}\n'
  printf '{"type":"turn.started"}\n'
  printf '{"type":"item.started","item":{"id":"item_0","type":"exec_command"}}\n'
  sleep 4
  exit 0
fi

echo "unexpected codex args: $*" >&2
exit 64
EOF

chmod +x "$bin_dir/python3" "$bin_dir/stat" "$bin_dir/codex"

printf '{"account":"ok"}\n' >"$home_dir/.codex/auth.json"
printf 'Portable runner prompt\n' >"$prompt_file"

git -C "$worktree" init -b test >/dev/null 2>&1

set +e
ACP_CODEX_PROGRESS_HEARTBEAT_SECONDS=1 \
ACP_CODEX_STALL_SECONDS=2 \
HOME="$home_dir" \
PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
bash "$SCRIPT" \
  --mode safe \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --output-file "$output_file" \
  --host-run-dir "$host_run_dir" \
  --sandbox-run-dir "$sandbox_run_dir" \
  --safe-profile demo-safe \
  --codex-bin "$bin_dir/codex" \
  --max-resume-attempts 1 \
  --auth-refresh-timeout-seconds 5 \
  --auth-refresh-poll-seconds 1
status=$?
set -e

test "$status" -ne 0
grep -q 'stale-run no-codex-progress-before-stall-threshold elapsed=' "$output_file"
grep -q '^RUNNER_STATE=failed$' "$runner_env"
grep -q '^LAST_FAILURE_REASON=no-codex-progress-before-stall-threshold$' "$runner_env"
test -s "$python_capture"

echo "agent-project-run-codex-resilient uses path python and gnu stat test passed"
