#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-claude-session"

tmpdir="$(mktemp -d)"
cleanup() {
  if tmux has-session -t "acp-issue-claude-reap" 2>/dev/null; then
    tmux kill-session -t "acp-issue-claude-reap" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="acp-issue-claude-reap"
run_dir="$runs_root/$session"
attempt_log="$run_dir/claude-attempt-1.log"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-claude-session"

cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

pid_file="${ACP_HOST_RUN_DIR:?}/fake-claude.pid"
trap 'printf "received TERM\n"; exit 143' TERM HUP INT
printf '%s\n' "$$" >"$pid_file"
printf 'stream-start\n'
while true; do
  sleep 1
done
EOF

chmod +x "$tools_dir/agent-project-run-claude-session" "$bin_dir/claude"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

PATH="$bin_dir:$PATH" \
bash "$tools_dir/agent-project-run-claude-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 123 \
  --claude-model sonnet \
  --claude-permission-mode dontAsk \
  --claude-effort medium \
  --claude-timeout-seconds 120 \
  --claude-max-attempts 1 \
  --claude-retry-backoff-seconds 0 \
  >/dev/null

for _ in $(seq 1 50); do
  if [[ -f "$run_dir/fake-claude.pid" ]]; then
    break
  fi
  sleep 0.1
done

test -f "$run_dir/fake-claude.pid"
fake_pid="$(cat "$run_dir/fake-claude.pid")"
[[ "$fake_pid" =~ ^[0-9]+$ ]]

for _ in $(seq 1 50); do
  if grep -q 'stream-start' "$attempt_log" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

grep -q 'stream-start' "$attempt_log"

tmux kill-session -t "$session" >/dev/null 2>&1 || true

for _ in $(seq 1 50); do
  if ! kill -0 "$fake_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if kill -0 "$fake_pid" 2>/dev/null; then
  echo "fake claude child was left running after parent termination" >&2
  exit 1
fi

echo "agent-project claude wrapper reaps child on term test passed"
