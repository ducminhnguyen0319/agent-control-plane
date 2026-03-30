#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_SRC="${FLOW_ROOT}/tools/bin/update-github-labels.sh"
CONFIG_LIB_SRC="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
SHELL_LIB_SRC="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
profile_home="$tmpdir/profiles"
log_file="$tmpdir/helper.log"

mkdir -p "$bin_dir" "$profile_home/demo"

cp "$SCRIPT_SRC" "$bin_dir/update-github-labels.sh"
cp "$CONFIG_LIB_SRC" "$bin_dir/flow-config-lib.sh"
cp "$SHELL_LIB_SRC" "$bin_dir/flow-shell-lib.sh"

cat >"$profile_home/demo/control-plane.yaml" <<'EOF'
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
EOF

cat >"$bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_HELPER_LOG:?}"
EOF

chmod +x \
  "$bin_dir/update-github-labels.sh" \
  "$bin_dir/flow-config-lib.sh" \
  "$bin_dir/flow-shell-lib.sh" \
  "$bin_dir/agent-github-update-labels"

TEST_HELPER_LOG="$log_file" \
ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
ACP_PROJECT_ID="demo" \
AGENT_CONTROL_PLANE_ROOT="$tmpdir/not-a-skill-root" \
bash "$bin_dir/update-github-labels.sh" 42 --add ready --remove blocked

grep -q -- '--repo-slug example/demo --number 42 --add ready --remove blocked' "$log_file"

echo "update-github-labels sibling helper test passed"
