#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-openclaw-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-issue-openclaw-session-progress"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
sub="${2:-}"
case "$cmd:$sub" in
  agents:add)
    mkdir -p .openclaw
    printf '{"agentId":"stub"}\n'
    ;;
  agent:*)
    shift 1 || true
    agent_id=""
    session_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent) agent_id="${2:-}"; shift 2 ;;
        --session-id) session_id="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done

    sessions_dir="${OPENCLAW_STATE_DIR:?}/agents/${agent_id}/sessions"
    session_file="${sessions_dir}/legacy-session.jsonl"
    mkdir -p "$sessions_dir" "${ACP_RUN_DIR:?}"
    printf '{"sessionId":"%s","sessionFile":"%s"}\n' "$session_id" "$session_file" >"${sessions_dir}/sessions.json"
    printf '{"type":"session","id":"legacy"}\n' >"$session_file"

    (
      sleep 0.6
      printf '{"type":"message","id":"tick-1"}\n' >>"$session_file"
      sleep 0.8
      printf '{"type":"message","id":"tick-2"}\n' >>"$session_file"
      sleep 1.2
      cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
RESULT
      printf '{"status":"pass","command":"mock verification"}\n' >"${ACP_RUN_DIR}/verification.jsonl"
    ) &
    wait "$!"
    ;;
  *)
    echo "unexpected openclaw args: $*" >&2
    exit 64
    ;;
esac
EOF

chmod +x "$tools_dir/agent-project-run-openclaw-session" "$bin_dir/openclaw"

git -C "$worktree" init -b test >/dev/null 2>&1
git -C "$worktree" config user.name "OpenClaw"
git -C "$worktree" config user.email "openclaw@example.com"
printf 'seed\n' >"$worktree/README.md"
git -C "$worktree" add README.md
git -C "$worktree" commit -m "init" >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

ACP_OPENCLAW_PROGRESS_HEARTBEAT_SECONDS=1 \
PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
bash "$tools_dir/agent-project-run-openclaw-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 123 \
  --openclaw-model mock/model \
  --openclaw-stall-seconds 2 \
  >/dev/null

for _ in $(seq 1 50); do
  if ! tmux has-session -t "$session" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session did not exit" >&2
  exit 1
fi

grep -q '^RUNNER_STATE=succeeded$' "$run_dir/runner.env"
grep -q '^OUTCOME=implemented$' "$run_dir/result.env"
if grep -q 'stale-run' "$run_dir/$session.log"; then
  echo "wrapper treated session-state progress as stalled" >&2
  exit 1
fi
grep -q '^\[openclaw\] heartbeat progress source=session-state elapsed=' "$run_dir/$session.log"

echo "agent-project openclaw session wrapper session-state progress test passed"
