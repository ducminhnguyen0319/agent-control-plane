#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/profile-activate.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"

bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id demo --repo-slug example/demo-platform >/dev/null
profile_notes_real="$(cd "$profile_home/demo" && pwd -P)/README.md"

output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SCRIPT" --profile-id demo)"

grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q "^PROFILE_REGISTRY_ROOT=${profile_home}$" <<<"$output"
grep -q "^CONFIG_YAML=${profile_home}/demo/control-plane.yaml$" <<<"$output"
grep -q "^PROFILE_NOTES=${profile_notes_real}$" <<<"$output"
grep -q '^REPO_SLUG=example/demo-platform$' <<<"$output"
grep -q '^CODING_WORKER=openclaw$' <<<"$output"
printf -v expected_next_step 'NEXT_STEP=eval "$(%s/tools/bin/profile-activate.sh --profile-id demo --exports)"' "${FLOW_ROOT}"
grep -Fqx "$expected_next_step" <<<"$output"

exports_out="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SCRIPT" --profile-id demo --exports)"
grep -q '^export ACP_PROJECT_ID=demo$' <<<"$exports_out"
grep -q '^export AGENT_PROJECT_ID=demo$' <<<"$exports_out"
grep -q "^export ACP_PROFILE_REGISTRY_ROOT=${profile_home}$" <<<"$exports_out"
grep -q "^export ACP_CONFIG=${profile_home}/demo/control-plane.yaml$" <<<"$exports_out"

echo "profile activate test passed"
