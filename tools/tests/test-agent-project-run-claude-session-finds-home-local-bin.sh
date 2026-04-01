#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-claude-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="acp-issue-claude-home-local-bin"
run_dir="$runs_root/$session"
fake_home="$tmpdir/home"
local_bin="$fake_home/.local/bin"
empty_path_dir="$tmpdir/empty-path"

mkdir -p "$tools_dir" "$worktree" "$runs_root" "$local_bin" "$empty_path_dir"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-claude-session"

cat >"$local_bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'USED_CLAUDE=%s\n' "$0" >"${ACP_HOST_RUN_DIR:?}/claude-bin-path.txt"
cat >"${ACP_HOST_RUN_DIR:?}/claude-debug.log" <<'DEBUG'
[ERROR] API error (attempt 1/11): 429 {"type":"error","error":{"type":"rate_limit_error","message":"This request would exceed your account's rate limit. Please try again later."}}
DEBUG
exit 1
EOF

chmod +x "$tools_dir/agent-project-run-claude-session" "$local_bin/claude"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

HOME="$fake_home" \
PATH="$empty_path_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
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
  --claude-max-attempts 3 \
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

grep -q "^USED_CLAUDE=${fake_home}/.local/bin/claude$" "$run_dir/claude-bin-path.txt"
grep -q "^CLAUDE_BIN=${fake_home}/.local/bin/claude$" "$run_dir/run.env"
grep -q '^LAST_FAILURE_REASON=provider-quota-limit$' "$run_dir/runner.env"

echo "agent-project run claude session finds home local bin test passed"
