#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

config_file="$tmpdir/control-plane.yaml"

cat >"$config_file" <<'EOF'
schema_version: "1"
id: "demo"
repo:
  slug: "example/repo"
  id: "123"
  default_branch: "main"
EOF

output="$(
  bash -lc 'source "'"$CONFIG_LIB"'"; flow_export_execution_env "'"$config_file"'"; printf "ACP_REPO_ID=%s\nF_LOSNING_REPO_ID=%s\nACP_GITHUB_REPOSITORY_ID=%s\nF_LOSNING_GITHUB_REPOSITORY_ID=%s\n" "${ACP_REPO_ID:-}" "${F_LOSNING_REPO_ID:-}" "${ACP_GITHUB_REPOSITORY_ID:-}" "${F_LOSNING_GITHUB_REPOSITORY_ID:-}"'
)"

grep -q '^ACP_REPO_ID=123$' <<<"$output"
grep -q '^F_LOSNING_REPO_ID=123$' <<<"$output"
grep -q '^ACP_GITHUB_REPOSITORY_ID=123$' <<<"$output"
grep -q '^F_LOSNING_GITHUB_REPOSITORY_ID=123$' <<<"$output"

echo "flow export execution env exports repo id test passed"
