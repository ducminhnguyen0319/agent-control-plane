#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"
RENDER_SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skill_root="$tmpdir/skill"
profile_home="$tmpdir/.agent-control-plane/profiles"
tools_bin_dir="$skill_root/tools/bin"
templates_dir="$skill_root/tools/templates"
assets_dir="$skill_root/assets"

mkdir -p "$tools_bin_dir" "$templates_dir" "$assets_dir"
cp "$SCAFFOLD_SCRIPT" "$tools_bin_dir/scaffold-profile.sh"
cp "$RENDER_SCRIPT" "$tools_bin_dir/render-flow-config.sh"
cp "$FLOW_CONFIG_LIB" "$tools_bin_dir/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$tools_bin_dir/flow-shell-lib.sh"
printf '{}\n' >"$assets_dir/workflow-catalog.json"
cp "$FLOW_ROOT/tools/templates/issue-prompt-template.md" "$templates_dir/issue-prompt-template.md"
cp "$FLOW_ROOT/tools/templates/scheduled-issue-prompt-template.md" "$templates_dir/scheduled-issue-prompt-template.md"
cp "$FLOW_ROOT/tools/templates/pr-fix-template.md" "$templates_dir/pr-fix-template.md"
cp "$FLOW_ROOT/tools/templates/pr-review-template.md" "$templates_dir/pr-review-template.md"
cp "$FLOW_ROOT/tools/templates/pr-merge-repair-template.md" "$templates_dir/pr-merge-repair-template.md"

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  bash "$tools_bin_dir/scaffold-profile.sh" \
    --profile-id alpha-demo \
    --repo-slug acme/alpha-demo
)"

profile_yaml="$profile_home/alpha-demo/control-plane.yaml"
profile_template_dir="$profile_home/alpha-demo/templates"
profile_readme="$profile_home/alpha-demo/README.md"
profile_home_real="$(mkdir -p "$profile_home" && cd "$profile_home" && pwd -P)"
profile_yaml_real="$(cd "$(dirname "$profile_yaml")" && pwd -P)/$(basename "$profile_yaml")"
profile_template_dir_real="$(cd "$profile_template_dir" && pwd -P)"
profile_readme_real="$(cd "$(dirname "$profile_readme")" && pwd -P)/$(basename "$profile_readme")"

test -f "$profile_yaml"
test -f "$profile_template_dir/issue-prompt-template.md"
test -f "$profile_readme"
test -f "$profile_template_dir/pr-review-template.md"
cmp -s "$templates_dir/issue-prompt-template.md" "$profile_template_dir/issue-prompt-template.md"
grep -q '^PROFILE_ID=alpha-demo$' <<<"$output"
grep -q "^PROFILE_HOME=${profile_home_real}$" <<<"$output"
grep -q "^PROFILE_YAML=${profile_yaml_real}$" <<<"$output"
grep -q "^PROFILE_TEMPLATE_DIR=${profile_template_dir_real}$" <<<"$output"
grep -q "^PROFILE_README=${profile_readme_real}$" <<<"$output"
grep -q '^REPO_SLUG=acme/alpha-demo$' <<<"$output"
grep -q '^  slug: "acme/alpha-demo"$' "$profile_yaml"
grep -q '^  issue_prefix: "alpha-demo-issue-"$' "$profile_yaml"
grep -q '^  pr_prefix: "alpha-demo-pr-"$' "$profile_yaml"
grep -q '^  issue_branch_prefix: "agent/alpha-demo/issue"$' "$profile_yaml"
grep -q '^  pr_worktree_branch_prefix: "agent/alpha-demo/pr"$' "$profile_yaml"
grep -q '^  coding_worker: "openclaw"$' "$profile_yaml"
grep -q '^  provider_quota:$' "$profile_yaml"
grep -q '^    cooldowns: "300,900,1800,3600"$' "$profile_yaml"
grep -q '^    model: "openrouter/qwen/qwen3.6-plus-preview:free"$' "$profile_yaml"
grep -q '^    thinking: "low"$' "$profile_yaml"
grep -q '^# alpha-demo Profile Notes$' "$profile_readme"
grep -q '^## Startup Checklist$' "$profile_readme"

render_output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  ACP_PROJECT_ID="alpha-demo" \
  bash "$tools_bin_dir/render-flow-config.sh"
)"

grep -q "^CONFIG_YAML=${profile_yaml}$" <<<"$render_output"
grep -q '^PROFILE_ID=alpha-demo$' <<<"$render_output"
grep -Eq '^AVAILABLE_PROFILES=alpha-demo$' <<<"$render_output"
grep -q '^EFFECTIVE_REPO_ROOT=/tmp/agent-control-plane-alpha-demo/repo$' <<<"$render_output"
grep -q '^EFFECTIVE_CODING_WORKER=openclaw$' <<<"$render_output"
grep -q '^EFFECTIVE_PROVIDER_QUOTA_COOLDOWNS=300,900,1800,3600$' <<<"$render_output"
grep -q '^EFFECTIVE_OPENCLAW_MODEL=openrouter/qwen/qwen3.6-plus-preview:free$' <<<"$render_output"

claude_output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  bash "$tools_bin_dir/scaffold-profile.sh" \
    --profile-id claude-demo \
    --repo-slug acme/claude-demo \
    --coding-worker claude \
    --claude-model opus \
    --claude-permission-mode bypassPermissions \
    --claude-effort max \
    --claude-timeout-seconds 321 \
    --claude-max-attempts 4 \
    --claude-retry-backoff-seconds 9
)"

claude_yaml="$profile_home/claude-demo/control-plane.yaml"
test -f "$claude_yaml"
grep -q '^PROFILE_ID=claude-demo$' <<<"$claude_output"
grep -q '^  coding_worker: "claude"$' "$claude_yaml"
grep -q '^    model: "opus"$' "$claude_yaml"
grep -q '^    permission_mode: "bypassPermissions"$' "$claude_yaml"
grep -q '^    effort: "max"$' "$claude_yaml"
grep -q '^    timeout_seconds: 321$' "$claude_yaml"
grep -q '^    max_attempts: 4$' "$claude_yaml"
grep -q '^    retry_backoff_seconds: 9$' "$claude_yaml"

echo "scaffold profile test passed"
