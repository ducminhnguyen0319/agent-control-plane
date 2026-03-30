#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_SMOKE_SCRIPT="${FLOW_ROOT}/tools/bin/profile-smoke.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"
RENDER_SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
profile_home="$tmpdir/.agent-control-plane/profiles"
tools_bin_dir="$skill_root/tools/bin"
assets_dir="$skill_root/assets"

mkdir -p "$tools_bin_dir" "$assets_dir"
cp "$PROFILE_SMOKE_SCRIPT" "$tools_bin_dir/profile-smoke.sh"
cp "$SCAFFOLD_SCRIPT" "$tools_bin_dir/scaffold-profile.sh"
cp "$RENDER_SCRIPT" "$tools_bin_dir/render-flow-config.sh"
cp "$FLOW_CONFIG_LIB" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$tools_bin_dir/flow-shell-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"

ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$tools_bin_dir/scaffold-profile.sh" --profile-id alpha --repo-slug acme/alpha >/dev/null
ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$tools_bin_dir/scaffold-profile.sh" --profile-id beta --repo-slug acme/beta >/dev/null

perl -0pi -e 's/issue_prefix: "beta-issue-"/issue_prefix: "alpha-issue-"/g' "$profile_home/beta/control-plane.yaml"

set +e
output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$tools_bin_dir/profile-smoke.sh" 2>&1)"
status=$?
set -e

test "$status" -eq 1
grep -q '^PROFILE_ID=alpha$' <<<"$output"
grep -q '^PROFILE_ID=beta$' <<<"$output"
grep -q '^DUPLICATE_ISSUE_PREFIX=alpha-issue-$' <<<"$output"
grep -Eq '^DUPLICATE_ISSUE_PREFIX_PROFILES=(alpha,beta|beta,alpha)$' <<<"$output"
grep -q '^PROFILE_SMOKE_STATUS=failed$' <<<"$output"

echo "profile smoke collision test passed"
