#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_PATH="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

flow_root="$tmpdir/flow-root"
shared_home="$tmpdir/shared-home"
custom_bin="$tmpdir/custom-codex-quota"
custom_script="$tmpdir/custom-auto-switch.sh"

mkdir -p \
  "$flow_root/tools/bin" \
  "$flow_root/tools/vendor/codex-quota-manager/scripts" \
  "$shared_home/tools/bin" \
  "$shared_home/tools/vendor/codex-quota-manager/scripts" \
  "$shared_home/skills/openclaw/codex-quota-manager/scripts"

cat >"$flow_root/tools/bin/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$flow_root/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_home/tools/bin/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_home/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$shared_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$custom_bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$custom_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$flow_root/tools/bin/codex-quota" \
  "$flow_root/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" \
  "$shared_home/tools/bin/codex-quota" \
  "$shared_home/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" \
  "$shared_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  "$custom_bin" \
  "$custom_script"

(
  export ACP_ROOT="$flow_root"
  export SHARED_AGENT_HOME="$shared_home"
  # shellcheck source=/dev/null
  source "$LIB_PATH"
  test "$(flow_resolve_codex_quota_bin "$flow_root")" = "$flow_root/tools/bin/codex-quota"
  test "$(flow_resolve_codex_quota_manager_script "$flow_root")" = "$flow_root/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"
)

rm -f "$flow_root/tools/bin/codex-quota" "$flow_root/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"

(
  export ACP_ROOT="$flow_root"
  export SHARED_AGENT_HOME="$shared_home"
  # shellcheck source=/dev/null
  source "$LIB_PATH"
  test "$(flow_resolve_codex_quota_bin "$flow_root")" = "$shared_home/tools/bin/codex-quota"
  test "$(flow_resolve_codex_quota_manager_script "$flow_root")" = "$shared_home/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"
)

(
  export ACP_ROOT="$flow_root"
  export SHARED_AGENT_HOME="$shared_home"
  export ACP_CODEX_QUOTA_BIN="$custom_bin"
  export ACP_CODEX_QUOTA_MANAGER_SCRIPT="$custom_script"
  # shellcheck source=/dev/null
  source "$LIB_PATH"
  test "$(flow_resolve_codex_quota_bin "$flow_root")" = "$custom_bin"
  test "$(flow_resolve_codex_quota_manager_script "$flow_root")" = "$custom_script"
)

echo "flow codex quota resolver test passed"
