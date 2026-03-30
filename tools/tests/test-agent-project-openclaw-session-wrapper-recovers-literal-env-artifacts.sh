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
session="fl-issue-openclaw-literal-env"
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
    printf 'state\n' >.openclaw/workspace-state.json
    : >SOUL.md
    : >TOOLS.md
    : >IDENTITY.md
    : >USER.md
    : >HEARTBEAT.md
    : >BOOTSTRAP.md
    printf '{"agentId":"stub"}\n'
    ;;
  agent:*)
    mkdir -p "$PWD/\$ACP_RUN_DIR"
    cat >"$PWD/\$ACP_RESULT_FILE" <<'RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
RESULT
    printf '{"status":"pass","command":"mock verification"}\n' >"$PWD/\$ACP_RUN_DIR/verification.jsonl"
    printf 'literal artifact\n' >"$PWD/\$ACP_RUN_DIR/mock.txt"
    printf '{"payloads":[{"text":"DONE"}]}\n'
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
  --collect-file verification.jsonl \
  --collect-file mock.txt \
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
test -f "$run_dir/verification.jsonl"
test -f "$run_dir/mock.txt"
grep -q '^OUTCOME=implemented$' "$run_dir/result.env"
grep -q '^ACTION=host-publish-issue-pr$' "$run_dir/result.env"
grep -q '"status":"pass"' "$run_dir/verification.jsonl"
grep -q 'literal artifact' "$run_dir/mock.txt"

if [[ -e "$worktree/\$ACP_RESULT_FILE" || -e "$worktree/\$ACP_RUN_DIR" ]]; then
  echo "literal env alias artifacts should be cleaned up" >&2
  exit 1
fi

status_output="$(git -C "$worktree" status --short)"
if [[ -n "$status_output" ]]; then
  echo "worktree unexpectedly dirty:" >&2
  printf '%s\n' "$status_output" >&2
  exit 1
fi

echo "agent-project openclaw session wrapper literal env artifact recovery test passed"
