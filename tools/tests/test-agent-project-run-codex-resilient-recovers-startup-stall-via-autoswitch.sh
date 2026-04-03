#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_BIN="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-startup-stall.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
worktree="$tmpdir/worktree"
host_run_dir="$tmpdir/run"
sandbox_run_dir="$tmpdir/sandbox"
prompt_file="$tmpdir/prompt.md"
output_file="$host_run_dir/run.log"
state_dir="$tmpdir/state"
shared_agent_home="$tmpdir/shared-agent-home"
quota_script_dir="$shared_agent_home/skills/openclaw/codex-quota-manager/scripts"

mkdir -p "$bin_dir" "$home_dir/.codex" "$worktree" "$host_run_dir" "$sandbox_run_dir" "$state_dir" "$quota_script_dir"

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_CODEX_STATE_DIR:?}"
active_label_file="${state_dir}/active-label"
active_label="$(cat "$active_label_file" 2>/dev/null || printf 'initial-over-limit')"

if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  printf 'Logged in using ChatGPT\n'
  exit 0
fi

if [[ "${1:-}" == "exec" ]]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"thread-startup-stall"}'
  printf '%s\n' '{"type":"turn.started"}'
  if [[ "$active_label" == "initial-over-limit" ]]; then
    sleep 10
    exit 143
  fi
  printf '%s\n' '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"resumed-on-rotated-account"}}'
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
  exit 0
fi

echo "unexpected codex args: $*" >&2
exit 64
EOF
chmod +x "$bin_dir/codex"

cat >"$bin_dir/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_CODEX_STATE_DIR:?}"
active_label="$(cat "${state_dir}/active-label" 2>/dev/null || printf 'initial-over-limit')"

if [[ "${1:-}" == "codex" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  cat <<JSON
{"activeInfo":{"trackedLabel":"${active_label}"},"accounts":[{"label":"${active_label}","isActive":true,"isNativeActive":false}]}
JSON
  exit 0
fi

exit 0
EOF
chmod +x "$bin_dir/codex-quota"

cat >"$quota_script_dir/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_CODEX_STATE_DIR:?}"
printf '%s\n' "$*" >>"${state_dir}/auto-switch.log"
printf 'rotated-ok\n' >"${state_dir}/active-label"
printf '{"account":"rotated","ts":"%s"}\n' "$(date +%s)" >"$HOME/.codex/auth.json"
printf 'SWITCH_DECISION=switched\n'
printf 'SELECTED_LABEL=rotated-ok\n'
printf 'Switched to rotated-ok.\n'
EOF
chmod +x "$quota_script_dir/auto-switch.sh"

printf '{"account":"initial"}\n' >"$home_dir/.codex/auth.json"
printf 'initial-over-limit\n' >"$state_dir/active-label"
printf 'Startup stall prompt\n' >"$prompt_file"
git -C "$worktree" init -b test >/dev/null 2>&1

MOCK_CODEX_STATE_DIR="$state_dir" \
ACP_CODEX_QUOTA_BIN="$bin_dir/codex-quota" \
ACP_CODEX_QUOTA_MANAGER_SCRIPT="$quota_script_dir/auto-switch.sh" \
ACP_CODEX_PROGRESS_HEARTBEAT_SECONDS=1 \
ACP_CODEX_STALL_SECONDS=2 \
ACP_CODEX_MAX_AUTOSWITCH_ATTEMPTS=1 \
SHARED_AGENT_HOME="$shared_agent_home" \
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

grep -q 'startup-stall detected before first Codex tool activity; attempting Codex account rotation' "$output_file"
grep -q 'Switched to rotated-ok.' "$output_file"
grep -q 'resumed-on-rotated-account' "$output_file"
grep -q '^RUNNER_STATE=succeeded$' "$host_run_dir/runner.env"
grep -q '^THREAD_ID=thread-startup-stall$' "$host_run_dir/runner.env"
grep -q 'startup-stall' "$output_file"

echo "agent-project-run-codex-resilient startup stall recovery test passed"
