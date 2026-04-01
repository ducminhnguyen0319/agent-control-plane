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
session="fl-issue-openclaw-failing-comment"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
sub="${2:-}"
case "$cmd:$sub" in
  agents:list)
    printf '[]\n'
    ;;
  agents:add)
    shift 2
    agent_dir=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent-dir) agent_dir="${2:-}"; shift 2 ;;
        --workspace|--model) shift 2 ;;
        --non-interactive|--json) shift ;;
        *) shift ;;
      esac
    done
    mkdir -p "${agent_dir:-/tmp/ignored}"
    printf '{"agentId":"stub"}\n'
    ;;
  agent:--agent)
    mkdir -p "${ACP_RUN_DIR:?}"
    cat <<'JSON'
{
  "payloads": [
    {
      "text": "Host blocker recovered from failing OpenClaw run"
    }
  ]
}
JSON
    exit 1
    ;;
  agents:delete)
    printf '{"deleted":true}\n'
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
  --collect-file issue-comment.md \
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
test -f "$run_dir/issue-comment.md"
test -f "$run_dir/runner.env"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"
grep -q '^RUNNER_STATE=failed$' "$run_dir/runner.env"
grep -q 'Host blocker recovered from failing OpenClaw run' "$run_dir/issue-comment.md"

echo "agent-project openclaw session wrapper synthesizes comment on failure test passed"
