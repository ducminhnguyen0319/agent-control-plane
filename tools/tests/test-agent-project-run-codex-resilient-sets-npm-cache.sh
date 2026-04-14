#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-npm-cache.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
worktree="$tmpdir/worktree"
host_run_dir="$tmpdir/run"
sandbox_run_dir="$tmpdir/sandbox"
prompt_file="$tmpdir/prompt.md"
output_file="$host_run_dir/run.log"
npm_capture="$tmpdir/npm-cache.txt"

mkdir -p "$bin_dir" "$home_dir/.codex" "$worktree" "$host_run_dir" "$sandbox_run_dir"

cat >"$bin_dir/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "login" && "\${2:-}" == "status" ]]; then
  printf 'Logged in using ChatGPT\n'
  exit 0
fi

printf '%s\n' "\${NPM_CONFIG_CACHE:-}" >"$npm_capture"
printf '{"type":"thread.started","thread_id":"thread-npm-cache"}\n'
printf '{"type":"turn.started"}\n'
exit 0
EOF

chmod +x "$bin_dir/codex"

printf '{"account":"ok"}\n' >"$home_dir/.codex/auth.json"
printf 'Prompt\n' >"$prompt_file"
git -C "$worktree" init -b test >/dev/null 2>&1

env -u NPM_CONFIG_CACHE -u npm_config_cache \
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
    --auth-refresh-poll-seconds 1 >/dev/null

expected_cache="$home_dir/.agent-runtime/npm-cache"
test "$(cat "$npm_capture")" = "$expected_cache"
test -d "$expected_cache"

echo "agent-project-run-codex-resilient sets npm cache test passed"
