#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

prompt_file="$tmpdir/prompt.md"
output_file="$tmpdir/output.log"
host_run_dir="$tmpdir/host-run"
sandbox_run_dir="$tmpdir/sandbox-run"
capture_file="$tmpdir/codex-env.log"
codex_bin="$tmpdir/codex"

mkdir -p "$host_run_dir" "$sandbox_run_dir" "$tmpdir/worktree"
printf 'test prompt\n' >"$prompt_file"

cat >"$codex_bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
env | sort >"${TEST_CAPTURE_FILE:?}"
printf '{"type":"thread.started","thread_id":"worker-thread"}\n'
exit 0
EOF
chmod +x "$codex_bin"

CODEX_THREAD_ID="outer-thread" \
TEST_CAPTURE_FILE="$capture_file" \
bash "$SCRIPT" \
  --mode safe \
  --worktree "$tmpdir/worktree" \
  --prompt-file "$prompt_file" \
  --output-file "$output_file" \
  --host-run-dir "$host_run_dir" \
  --sandbox-run-dir "$sandbox_run_dir" \
  --safe-profile demo-safe \
  --bypass-profile demo-bypass \
  --codex-bin "$codex_bin" \
  >/dev/null

if grep -q '^CODEX_THREAD_ID=' "$capture_file"; then
  echo "nested codex worker inherited parent CODEX_THREAD_ID" >&2
  exit 1
fi

grep -q '^THREAD_ID=worker-thread$' "$host_run_dir/runner.env"

echo "agent-project-run-codex-resilient unsets parent thread env test passed"
