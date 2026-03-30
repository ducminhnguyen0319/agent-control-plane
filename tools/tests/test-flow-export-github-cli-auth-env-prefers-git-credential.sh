#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "credential" && "${2:-}" == "fill" ]]; then
  cat >/dev/null
  printf 'protocol=https\n'
  printf 'host=github.com\n'
  printf 'username=test-user\n'
  printf 'password=repo-specific-token\n'
  exit 0
fi
exit 1
EOF
chmod +x "$bin_dir/git"

output="$(
  LIB_PATH="$bin_dir/flow-config-lib.sh" \
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  GITHUB_PERSONAL_ACCESS_TOKEN="env-fallback-token" \
  bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"
unset GH_TOKEN
unset GITHUB_TOKEN
flow_export_github_cli_auth_env "owner/repo"
printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-}"
EOF
)"

grep -q '^GH_TOKEN=repo-specific-token$' <<<"$output"

echo "flow export github cli auth env prefers git credential test passed"
