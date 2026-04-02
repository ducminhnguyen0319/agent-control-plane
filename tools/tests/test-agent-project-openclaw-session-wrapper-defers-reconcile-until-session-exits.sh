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
session="fl-openclaw-defer-reconcile"
run_dir="$runs_root/$session"
reconcile_marker="$tmpdir/reconcile.marker"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
sub="${2:-}"
case "$cmd:$sub" in
  agents:add)
    printf '{"agentId":"stub"}\n'
    ;;
  agent:*)
    sleep 2
    cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=reported
ACTION=host-comment-scheduled-report
RESULT
    printf '{"payloads":[{"text":"DONE"}]}\n'
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
  --task-kind pr \
  --task-id 55 \
  --openclaw-model mock/model \
  --reconcile-command "printf reconciled > $reconcile_marker" \
  >/dev/null

sleep 0.5
if [[ -f "$reconcile_marker" ]]; then
  echo "reconcile should not run while tmux session is still active" >&2
  exit 1
fi
tmux has-session -t "$session" 2>/dev/null

for _ in $(seq 1 60); do
  if [[ -f "$reconcile_marker" ]] && ! tmux has-session -t "$session" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session did not exit" >&2
  exit 1
fi

test -f "$reconcile_marker"
test -f "$run_dir/result.env"

echo "agent-project openclaw session wrapper defers reconcile test passed"
