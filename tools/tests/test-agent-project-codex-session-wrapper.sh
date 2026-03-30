#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-codex-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-pr-wrapper-test"
run_dir="$runs_root/$session"
reconcile_log="$tmpdir/reconcile.log"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-codex-session"

cat >"$tools_dir/agent-project-run-codex-resilient" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sandbox_run_dir=""
output_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox-run-dir) sandbox_run_dir="${2:-}"; shift 2 ;;
    --output-file) output_file="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$sandbox_run_dir"
cat >"${sandbox_run_dir}/result.env" <<'RESULT'
OUTCOME=blocked
ACTION=host-comment-blocker
RESULT
printf 'artifact-from-runner\n' >"${sandbox_run_dir}/mock.txt"
printf 'mock runner wrote artifacts before failing\n' >>"$output_file"
exit 23
EOF

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "$tools_dir/agent-project-run-codex-session" "$bin_dir/codex"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

bash "$tools_dir/agent-project-run-codex-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind pr \
  --task-id 123 \
  --safe-profile mock-safe \
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

for _ in $(seq 1 25); do
  [[ -f "$reconcile_log" ]] && break
  sleep 0.2
done

test -f "$run_dir/result.env"
test -f "$run_dir/mock.txt"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"
grep -q 'artifact-from-runner' "$run_dir/mock.txt"
grep -q '__CODEX_EXIT__:23' "$run_dir/$session.log"
grep -q '^reconciled$' "$reconcile_log"

echo "agent-project codex session wrapper test passed"
