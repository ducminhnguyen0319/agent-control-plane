#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-claude-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="acp-issue-claude-retry"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-claude-session"

cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

attempt_file="${ACP_HOST_RUN_DIR:?}/attempt-count"
attempt="0"
if [[ -f "$attempt_file" ]]; then
  attempt="$(cat "$attempt_file")"
fi
attempt="$((attempt + 1))"
printf '%s' "$attempt" >"$attempt_file"

if [[ "$attempt" -eq 1 ]]; then
  printf 'network error: ECONNRESET\n' >&2
  exit 1
fi

cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=blocked
ACTION=host-comment-blocker
RESULT
printf 'retry success\n'
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
  --claude-timeout-seconds 10 \
  --claude-max-attempts 2 \
  --claude-retry-backoff-seconds 0 \
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

test -f "$run_dir/result.env"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"
grep -q '^2$' "$run_dir/attempt-count"
grep -q '^RUNNER_STATE=succeeded$' "$run_dir/runner.env"
grep -q '^ATTEMPT=2$' "$run_dir/runner.env"
grep -q '^RESUME_COUNT=1$' "$run_dir/runner.env"
grep -q '\[claude-retry\] reason=network-connection backoff=0s' "$run_dir/$session.log"
grep -q '__CODEX_EXIT__:0' "$run_dir/$session.log"

echo "agent-project claude retry wrapper test passed"
