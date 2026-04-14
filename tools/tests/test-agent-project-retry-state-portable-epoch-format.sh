#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-retry-state"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/retry-state-portable-date.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
state_root="$tmpdir/state"
mkdir -p "$bin_dir" "$state_root"

real_date="$(command -v date)"
real_python="$(command -v python3 2>/dev/null || command -v python)"

cat >"$bin_dir/date" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "+%s" ]]; then
  exec "$real_date" "+%s"
fi

if [[ "\${1:-}" == "-u" && "\${2:-}" == "+%Y-%m-%dT%H:%M:%SZ" ]]; then
  exec "$real_date" -u "+%Y-%m-%dT%H:%M:%SZ"
fi

if [[ "\${1:-}" == "-u" && "\${2:-}" == "-r" ]]; then
  echo "date: \${3:-}: No such file or directory" >&2
  exit 1
fi

if [[ "\${1:-}" == "-u" && "\${2:-}" == "-d" ]]; then
  exec "$real_date" -u -d "\${3:-}" "\${4:-}"
fi

echo "unexpected date args: \$*" >&2
exit 64
EOF

cat >"$bin_dir/python3" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$real_python" "\$@"
EOF

chmod +x "$bin_dir/date" "$bin_dir/python3"

state_out="$(
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  AGENT_PROJECT_STATE_ROOT="$state_root" \
  AGENT_PROJECT_RETRY_COOLDOWNS="300,900" \
  bash "$SCRIPT" \
    --state-root "$state_root" \
    --kind github \
    --item-id core-api \
    --action schedule \
    --reason github-api-rate-limit \
    --next-at-epoch 4102444800
)"

grep -q '^READY=no$' <<<"$state_out"
grep -q '^NEXT_ATTEMPT_EPOCH=4102444800$' <<<"$state_out"
grep -q '^NEXT_ATTEMPT_AT=2100-01-01T00:00:00Z$' <<<"$state_out"

echo "agent-project-retry-state portable epoch format test passed"
