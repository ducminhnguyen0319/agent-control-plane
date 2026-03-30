#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-live-thread.XXXXXX")"
cleanup() {
  if [[ -n "${runner_pid:-}" ]]; then
    kill "${runner_pid}" 2>/dev/null || true
    wait "${runner_pid}" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

bin_dir="$tmpdir/bin"
host_run_dir="$tmpdir/run"
sandbox_run_dir="$tmpdir/sandbox"
worktree_dir="$tmpdir/worktree"
prompt_file="$tmpdir/prompt.md"
output_file="$host_run_dir/output.log"
runner_copy="$tmpdir/agent-project-run-codex-resilient"
mock_codex="$bin_dir/codex"
state_file="$host_run_dir/runner.env"

mkdir -p "$bin_dir" "$host_run_dir" "$sandbox_run_dir" "$worktree_dir"
cp "$RUNNER_SRC" "$runner_copy"
chmod +x "$runner_copy"
echo "resume me later" >"$prompt_file"

cat >"$mock_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "exec" ]]; then
  echo '{"type":"thread.started","thread_id":"thread-live-123"}'
  sleep 2
  echo '{"type":"turn.started"}'
  sleep 1
  exit 0
fi

echo "unexpected args: $*" >&2
exit 1
EOF
chmod +x "$mock_codex"

bash "$runner_copy" \
  --mode safe \
  --worktree "$worktree_dir" \
  --prompt-file "$prompt_file" \
  --output-file "$output_file" \
  --host-run-dir "$host_run_dir" \
  --sandbox-run-dir "$sandbox_run_dir" \
  --safe-profile test-safe \
  --bypass-profile test-bypass \
  --codex-bin "$mock_codex" &
runner_pid=$!

for _ in $(seq 1 20); do
  if [[ -f "$state_file" ]] && grep -q '^THREAD_ID=thread-live-123$' "$state_file"; then
    break
  fi
  sleep 0.2
done

grep -q '^THREAD_ID=thread-live-123$' "$state_file"
kill -0 "$runner_pid"

wait "$runner_pid"

grep -q '^RUNNER_STATE=succeeded$' "$state_file"
grep -q '"thread_id":"thread-live-123"' "$output_file"

echo "test-agent-project-codex-live-thread-persist: PASS"
