#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"
repo_slug="example-owner/alpha"

bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id alpha --repo-slug "$repo_slug" >/dev/null
bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id demo --repo-slug example/demo-platform >/dev/null
profile_notes_real="$(cd "$profile_home/alpha" && pwd -P)/README.md"

# render-flow-config.sh unsets ambient ACP_CODING_WORKER / ACP_CLAUDE_* /
# ACP_OPENCLAW_* env vars so they cannot leak across profiles.  Only
# ACP_AGENT_REPO_ROOT (a runtime path, not a per-profile setting) is still
# honoured.  All execution settings come from the scaffold YAML defaults.
output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_AGENT_REPO_ROOT="/tmp/agent-repo" \
  bash "$SCRIPT"
)"

grep -q '^FLOW_SKILL_DIR=' <<<"$output"
grep -q "^CONFIG_YAML=${profile_home}/alpha/control-plane.yaml$" <<<"$output"
grep -q '^PROFILE_ID=alpha$' <<<"$output"
grep -q '^PROFILE_NOTES_EXISTS=yes$' <<<"$output"
grep -q "^PROFILE_NOTES=${profile_notes_real}$" <<<"$output"
grep -q '^PROFILE_SELECTION_HINT=Set ACP_PROJECT_ID=<id> or AGENT_PROJECT_ID=<id> when multiple available profiles exist\.$' <<<"$output"
grep -q '^PROFILE_SELECTION_MODE=implicit-default$' <<<"$output"
grep -q '^EFFECTIVE_AGENT_REPO_ROOT=/tmp/agent-repo$' <<<"$output"
# execution settings come from YAML (scaffold defaults), not env vars
grep -q '^EFFECTIVE_CODING_WORKER=openclaw$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_QUOTA_COOLDOWNS=300,900,1800,3600$' <<<"$output"
grep -q '^EFFECTIVE_CODEX_PROFILE_SAFE=alpha_safe$' <<<"$output"
grep -q '^EFFECTIVE_CODEX_PROFILE_BYPASS=alpha_bypass$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_MODEL=sonnet$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_PERMISSION_MODE=acceptEdits$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_EFFORT=medium$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_TIMEOUT_SECONDS=900$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_MAX_ATTEMPTS=3$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_RETRY_BACKOFF_SECONDS=30$' <<<"$output"
grep -q '^EFFECTIVE_OPENCLAW_MODEL=openrouter/qwen/qwen3.6-plus-preview:free$' <<<"$output"

echo "render flow config test passed"
