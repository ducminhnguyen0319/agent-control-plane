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

if [[ "${1:-}" == "api" && "${2:-}" == "repos/example/repo/issues/42" ]]; then
  echo "gh: API rate limit exceeded (HTTP 403)" >&2
  exit 1
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

if flow_github_api_repo "example/repo" "issues/42" >/dev/null; then
  echo "flow_github_api_repo should fail on GitHub core rate limit" >&2
  exit 1
fi

first_call_count="$(wc -l <"${TEST_GH_LOG}" | tr -d ' ')"
if flow_github_api_repo "example/repo" "issues/42" >/dev/null; then
  echo "flow_github_api_repo should stay blocked while cooldown is active" >&2
  exit 1
fi
second_call_count="$(wc -l <"${TEST_GH_LOG}" | tr -d ' ')"

test "${first_call_count}" = "1"
test "${second_call_count}" = "1"
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

echo "flow github api repo reacts to core rate limit test passed"
