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
session="fl-codex-openspec-shim-test"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree/openspec/changes/demo-change" "$worktree/openspec/specs/demo-spec" "$runs_root"
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
command -v openspec >>"$output_file"
printf 'changes:%s\n' "$(openspec list | tr '\n' ',' | sed 's/,$//')" >>"$output_file"
printf 'specs:%s\n' "$(openspec list --specs | tr '\n' ',' | sed 's/,$//')" >>"$output_file"
cat >"${sandbox_run_dir}/result.env" <<'RESULT'
OUTCOME=blocked
ACTION=host-comment-blocker
ISSUE_ID=1
RESULT
EOF

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "$tools_dir/agent-project-run-codex-session" "$tools_dir/agent-project-run-codex-resilient" "$bin_dir/codex"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
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

grep -q '/worker-bin/openspec$' "$run_dir/$session.log"
grep -q '^changes:demo-change$' "$run_dir/$session.log"
grep -q '^specs:demo-spec$' "$run_dir/$session.log"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"

echo "agent-project codex session wrapper provides openspec shim test passed"
