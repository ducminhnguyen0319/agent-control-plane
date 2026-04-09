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
session="acp-issue-claude-wrapper"
run_dir="$runs_root/$session"
reconcile_log="$tmpdir/reconcile.log"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-claude-session"

cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${ACP_HOST_RUN_DIR:?}/claude-args.log"
cat >"${ACP_HOST_RUN_DIR:?}/claude-stdin.log"
cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=blocked
ACTION=host-comment-blocker
RESULT
printf 'artifact-from-claude\n' >"${ACP_RUN_DIR:?}/mock.txt"
printf 'session-env\n' >".agent-session.env"
mkdir -p ".openclaw-artifacts"
printf 'generated\n' >".openclaw-artifacts/generated.txt"
printf 'mock claude finished\n'
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
  --claude-effort high \
  --collect-file mock.txt \
  --reconcile-command "printf 'reconciled\n' >> '$reconcile_log'" \
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

for _ in $(seq 1 100); do
  [[ -f "$reconcile_log" ]] && break
  sleep 0.2
done

test -f "$run_dir/result.env"
test -f "$run_dir/mock.txt"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"
grep -q 'artifact-from-claude' "$run_dir/mock.txt"
grep -q '__CODEX_EXIT__:0' "$run_dir/$session.log"
grep -q '^reconciled$' "$reconcile_log"
grep -q '^-p$' "$run_dir/claude-args.log"
grep -q '^--model$' "$run_dir/claude-args.log"
grep -q '^sonnet$' "$run_dir/claude-args.log"
grep -q '^--permission-mode$' "$run_dir/claude-args.log"
grep -q '^acceptEdits$' "$run_dir/claude-args.log"
grep -q '^--effort$' "$run_dir/claude-args.log"
grep -q '^high$' "$run_dir/claude-args.log"
grep -q '^--verbose$' "$run_dir/claude-args.log"
grep -q '^--allowed-tools$' "$run_dir/claude-args.log"
grep -Fqx 'Bash(*),Read,Grep,Glob,LS,Edit,Write,MultiEdit' "$run_dir/claude-args.log"
grep -q '^--disable-slash-commands$' "$run_dir/claude-args.log"
grep -q '^--strict-mcp-config$' "$run_dir/claude-args.log"
grep -q '^--mcp-config$' "$run_dir/claude-args.log"
grep -q '^--settings$' "$run_dir/claude-args.log"
grep -q '^--debug-file$' "$run_dir/claude-args.log"
grep -q '^--add-dir$' "$run_dir/claude-args.log"
if grep -Fxq 'Prompt body' "$run_dir/claude-args.log"; then
  echo "prompt body should be sent via stdin, not argv" >&2
  exit 1
fi
grep -Fxq 'Prompt body' "$run_dir/claude-stdin.log"
grep -Fqx 'CLAUDE_PERMISSION_MODE=dontAsk' "$run_dir/run.env"
grep -Fqx 'CLAUDE_EFFECTIVE_PERMISSION_MODE=acceptEdits' "$run_dir/run.env"
settings_file="$(awk 'prev == "--settings" { print; exit } { prev = $0 }' "$run_dir/claude-args.log")"
mcp_config_file="$(awk 'prev == "--mcp-config" { print; exit } { prev = $0 }' "$run_dir/claude-args.log")"
test -f "$settings_file"
test -f "$mcp_config_file"
grep -q '"disableAllHooks": true' "$settings_file"
grep -q '"mcpServers": {}' "$mcp_config_file"
exclude_file="$(git -C "$worktree" config --worktree --get core.excludesFile)"
test -f "$exclude_file"
grep -qx '.openclaw-artifacts' "$exclude_file"
grep -qx '.agent-session.env' "$exclude_file"
hook_path="$(git -C "$worktree" rev-parse --git-path hooks/pre-commit)"
if [[ "$hook_path" != /* ]]; then
  hook_path="$worktree/$hook_path"
fi
test -x "$hook_path"
test -z "$(git -C "$worktree" status --short)"

echo "agent-project claude session wrapper test passed"
