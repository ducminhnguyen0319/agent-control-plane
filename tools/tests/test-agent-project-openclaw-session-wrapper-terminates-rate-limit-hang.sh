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
session="openclaw-rate-limit-hang"
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
    printf '{"agents":[]}\n'
    ;;
  agents:add)
    shift 2 || true
    printf '{"agentId":"%s"}\n' "${1:-agent}"
    ;;
  agent:*)
    printf '429 Provider returned error stepfun/step-3.5-flash:free is temporarily rate-limited upstream.\n' >&2
    trap 'exit 1' TERM INT
    while true; do
      sleep 1
    done
    ;;
  *)
    echo "unexpected openclaw args: $cmd $sub $*" >&2
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
  --openclaw-timeout-seconds 30 \
  >/dev/null

for _ in $(seq 1 50); do
  if ! tmux has-session -t "$session" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session did not exit after rate limit hang" >&2
  exit 1
fi

test -f "$run_dir/runner.env"
grep -q '^RUNNER_STATE=failed$' "$run_dir/runner.env"
grep -q '^LAST_FAILURE_REASON=provider-quota-limit$' "$run_dir/runner.env"
grep -q 'rate-limited upstream' "$run_dir/$session.log"

echo "agent-project openclaw session wrapper terminates rate limit hang test passed"
