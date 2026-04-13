#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-codex-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-bin-precedence.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
path_bin_dir="$tmpdir/path-bin"
home_dir="$tmpdir/home"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-codex-bin-precedence"
run_dir="$runs_root/$session"

mkdir -p \
  "$tools_dir" \
  "$path_bin_dir" \
  "$home_dir/.nvm/versions/node/v99.0.0/bin" \
  "$worktree" \
  "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-codex-session"

cat >"$tools_dir/agent-project-run-codex-resilient" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sandbox_run_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox-run-dir) sandbox_run_dir="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$sandbox_run_dir"
cat >"${sandbox_run_dir}/result.env" <<'RESULT'
OUTCOME=blocked
ACTION=host-comment-blocker
RESULT
EOF

cat >"$path_bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'codex-cli 0.1.0\n'
  exit 0
fi
exit 0
EOF

cat >"$home_dir/.nvm/versions/node/v99.0.0/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'codex-cli 9.9.9\n'
  exit 0
fi
exit 0
EOF

chmod +x \
  "$tools_dir/agent-project-run-codex-session" \
  "$tools_dir/agent-project-run-codex-resilient" \
  "$path_bin_dir/codex" \
  "$home_dir/.nvm/versions/node/v99.0.0/bin/codex"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

HOME="$home_dir" \
PATH="$path_bin_dir:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
bash "$tools_dir/agent-project-run-codex-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 1 \
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

grep -q "^CODEX_BIN=$path_bin_dir/codex$" "$run_dir/run.env"

echo "agent-project codex session wrapper prefers path codex test passed"
