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

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_AGENT_REPO_ROOT="/tmp/agent-repo" \
  ACP_CODING_WORKER="codex" \
  ACP_CLAUDE_MODEL="sonnet" \
  ACP_CLAUDE_PERMISSION_MODE="dontAsk" \
  ACP_CLAUDE_EFFORT="high" \
  ACP_CLAUDE_TIMEOUT_SECONDS="777" \
  ACP_CLAUDE_MAX_ATTEMPTS="5" \
  ACP_CLAUDE_RETRY_BACKOFF_SECONDS="12" \
  ACP_OPENCLAW_MODEL="override/model" \
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
grep -q '^EFFECTIVE_CODING_WORKER=codex$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_QUOTA_COOLDOWNS=300,900,1800,3600$' <<<"$output"
grep -q '^EFFECTIVE_CODEX_PROFILE_SAFE=alpha_safe$' <<<"$output"
grep -q '^EFFECTIVE_CODEX_PROFILE_BYPASS=alpha_bypass$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_MODEL=sonnet$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_PERMISSION_MODE=dontAsk$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_EFFORT=high$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_TIMEOUT_SECONDS=777$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_MAX_ATTEMPTS=5$' <<<"$output"
grep -q '^EFFECTIVE_CLAUDE_RETRY_BACKOFF_SECONDS=12$' <<<"$output"
grep -q '^EFFECTIVE_OPENCLAW_MODEL=override/model$' <<<"$output"

echo "render flow config test passed"
