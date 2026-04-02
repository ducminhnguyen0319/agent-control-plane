#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_BIN="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-heartbeat.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
worktree="$tmpdir/worktree"
host_run_dir="$tmpdir/run"
sandbox_run_dir="$tmpdir/sandbox"
prompt_file="$tmpdir/prompt.md"
output_file="$host_run_dir/run.log"
runner_env="$host_run_dir/runner.env"

mkdir -p "$bin_dir" "$home_dir/.codex" "$worktree" "$host_run_dir" "$sandbox_run_dir"

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  printf 'Logged in using ChatGPT\n'
  exit 0
fi

if [[ "${1:-}" == "exec" ]]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"thread-heartbeat"}'
  sleep 2
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
  exit 0
fi

echo "unexpected codex args: $*" >&2
exit 64
EOF
chmod +x "$bin_dir/codex"

printf '{"account":"ok"}\n' >"$home_dir/.codex/auth.json"
printf 'Heartbeat test prompt\n' >"$prompt_file"

git -C "$worktree" init -b test >/dev/null 2>&1

ACP_CODEX_PROGRESS_HEARTBEAT_SECONDS=1 \
HOME="$home_dir" \
PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
bash "$HELPER_BIN" \
  --mode safe \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --output-file "$output_file" \
  --host-run-dir "$host_run_dir" \
  --sandbox-run-dir "$sandbox_run_dir" \
  --safe-profile mock-safe \
  --codex-bin "$bin_dir/codex" \
  --max-resume-attempts 1 \
  --auth-refresh-timeout-seconds 5 \
  --auth-refresh-poll-seconds 1

grep -q '^\[[0-9T:-]\+Z\] heartbeat waiting-for-codex-output elapsed=' "$output_file"
grep -q '^RUNNER_STATE=succeeded$' "$runner_env"
grep -q '^THREAD_ID=thread-heartbeat$' "$runner_env"

echo "agent-project-run-codex-resilient heartbeat test passed"
