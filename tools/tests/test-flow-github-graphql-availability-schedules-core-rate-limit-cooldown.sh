#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
GITHUB_RATE_LIMIT_STATE="${FLOW_ROOT}/tools/bin/github-core-rate-limit-state.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
state_root="$tmpdir/state"
gh_log="$tmpdir/gh.log"
mkdir -p "$bin_dir" "$state_root"

cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${TEST_GH_LOG:?}"

if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  cat <<'JSON'
{"resources":{"graphql":{"remaining":100},"core":{"remaining":0,"reset":4102444800}}}
JSON
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 97
EOF

chmod +x "$bin_dir/flow-config-lib.sh" "$bin_dir/flow-shell-lib.sh" "$bin_dir/gh"

LIB_PATH="$bin_dir/flow-config-lib.sh" \
PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
GH_TOKEN="test-token" \
TEST_GH_LOG="$gh_log" \
AGENT_CONTROL_PLANE_ROOT="$FLOW_ROOT" \
ACP_STATE_ROOT="$state_root" \
ACP_RETRY_COOLDOWNS="300,900" \
bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"

if flow_github_graphql_available "example/repo"; then
  echo "graphql should be unavailable when core quota is exhausted" >&2
  exit 1
fi
EOF

state_out="$(
  GH_TOKEN="test-token" \
  AGENT_CONTROL_PLANE_ROOT="$FLOW_ROOT" \
  ACP_STATE_ROOT="$state_root" \
  ACP_RETRY_COOLDOWNS="300,900" \
  bash "$GITHUB_RATE_LIMIT_STATE" get
)"

grep -q '^READY=no$' <<<"$state_out"
grep -q '^LAST_REASON=github-api-rate-limit$' <<<"$state_out"
test "$(wc -l <"$gh_log" | tr -d ' ')" -ge 1

echo "flow github graphql availability schedules core rate limit cooldown test passed"
