#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="${FLOW_ROOT}/tools/bin/sync-shared-agent-home.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_home="$tmpdir/source-home"
target_home="$tmpdir/runtime-home"
profile_home="$tmpdir/profiles"
legacy_template="${FLOW_ROOT}/tools/templates/legacy/issue-prompt-template-pre-slim.md"
current_template="${FLOW_ROOT}/tools/templates/issue-prompt-template.md"

mkdir -p \
  "$source_home/tools/bin" \
  "$source_home/skills/openclaw/codex-quota-manager/scripts" \
  "$profile_home/legacy-demo/templates" \
  "$profile_home/custom-demo/templates"

cat >"$source_home/tools/bin/test-shared-tool" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf 'shared-tool-ok\n'
INNER

cat >"$source_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf 'quota-switch-ok\n'
INNER

chmod +x \
  "$source_home/tools/bin/test-shared-tool" \
  "$source_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"

printf 'schema_version: "1"\nid: "legacy-demo"\n' >"$profile_home/legacy-demo/control-plane.yaml"
printf 'schema_version: "1"\nid: "custom-demo"\n' >"$profile_home/custom-demo/control-plane.yaml"
cp "$legacy_template" "$profile_home/legacy-demo/templates/issue-prompt-template.md"
cat >"$profile_home/custom-demo/templates/issue-prompt-template.md" <<'EOF'
# Task

Custom profile prompt override.
EOF

ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SYNC_SCRIPT" "$source_home" "$target_home" >/dev/null

cmp -s "$current_template" "$profile_home/legacy-demo/templates/issue-prompt-template.md"
grep -q '^# Required Contract$' "$profile_home/legacy-demo/templates/issue-prompt-template.md"
grep -q '^Custom profile prompt override\.$' "$profile_home/custom-demo/templates/issue-prompt-template.md"

echo "sync-shared-agent-home refreshes legacy issue profile template test passed"
