#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  scaffold-profile.sh --profile-id <id> --repo-slug <owner/repo> [options]

Create a new installed project profile, profile templates, and profile notes.

Options:
  --profile-id <id>                  Profile id, e.g. billing-api
  --repo-slug <owner/repo>           GitHub repo slug
  --profile-home <path>              Profile registry root (default: ~/.agent-runtime/control-plane/profiles)
  --repo-root <path>                 Canonical repo root
  --agent-repo-root <path>           Agent-owned anchor repo root (defaults to repo root)
  --agent-root <path>                Orchestrator runtime root
  --worktree-root <path>             Worktree parent root
  --retained-repo-root <path>        Optional retained/manual checkout root
  --vscode-workspace-file <path>     Optional VS Code workspace file
  --coding-worker <codex|openclaw|claude|ollama|pi|opencode|kilo>
                                     Default coding backend (default: openclaw)
  --claude-model <model>             Claude model alias or full name
  --claude-permission-mode <mode>    Claude permission mode (default: acceptEdits)
  --claude-effort <level>            Claude effort level (default: medium)
  --claude-timeout-seconds <secs>    Claude timeout (default: 900)
  --claude-max-attempts <count>      Claude retry attempts (default: 3)
  --claude-retry-backoff-seconds <s> Claude retry backoff (default: 30)
  --openclaw-model <model>           OpenClaw model string
  --openclaw-thinking <mode>         OpenClaw thinking mode
  --openclaw-timeout-seconds <secs>  OpenClaw timeout (default: 600)
  --force                            Overwrite existing profile files
  --help                             Show this help
EOF
}

profile_id=""
repo_slug=""
profile_home=""
repo_root=""
agent_repo_root=""
agent_root=""
worktree_root=""
retained_repo_root=""
vscode_workspace_file=""
coding_worker="openclaw"
claude_model="sonnet"
claude_permission_mode="acceptEdits"
claude_effort="medium"
claude_timeout_seconds="900"
claude_max_attempts="3"
claude_retry_backoff_seconds="30"
openclaw_model="openrouter/qwen/qwen3.6-plus-preview:free"
openclaw_thinking="low"
openclaw_timeout_seconds="600"
force="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id="${2:-}"; shift 2 ;;
    --repo-slug) repo_slug="${2:-}"; shift 2 ;;
    --profile-home) profile_home="${2:-}"; shift 2 ;;
    --repo-root) repo_root="${2:-}"; shift 2 ;;
    --agent-repo-root) agent_repo_root="${2:-}"; shift 2 ;;
    --agent-root) agent_root="${2:-}"; shift 2 ;;
    --worktree-root) worktree_root="${2:-}"; shift 2 ;;
    --retained-repo-root) retained_repo_root="${2:-}"; shift 2 ;;
    --vscode-workspace-file) vscode_workspace_file="${2:-}"; shift 2 ;;
    --coding-worker) coding_worker="${2:-}"; shift 2 ;;
    --claude-model) claude_model="${2:-}"; shift 2 ;;
    --claude-permission-mode) claude_permission_mode="${2:-}"; shift 2 ;;
    --claude-effort) claude_effort="${2:-}"; shift 2 ;;
    --claude-timeout-seconds) claude_timeout_seconds="${2:-}"; shift 2 ;;
    --claude-max-attempts) claude_max_attempts="${2:-}"; shift 2 ;;
    --claude-retry-backoff-seconds) claude_retry_backoff_seconds="${2:-}"; shift 2 ;;
    --openclaw-model) openclaw_model="${2:-}"; shift 2 ;;
    --openclaw-thinking) openclaw_thinking="${2:-}"; shift 2 ;;
    --openclaw-timeout-seconds) openclaw_timeout_seconds="${2:-}"; shift 2 ;;
    --force) force="1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$profile_id" || -z "$repo_slug" ]]; then
  usage >&2
  exit 1
fi

if [[ ! "$profile_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "--profile-id must match ^[a-z0-9][a-z0-9-]*$" >&2
  exit 1
fi

case "$coding_worker" in
  codex|openclaw|claude|ollama|pi|opencode|kilo) ;;
  *)
    echo "--coding-worker must be codex, openclaw, claude, ollama, pi, opencode, or kilo" >&2
    exit 1
    ;;
esac

case "$claude_effort" in
  low|medium|high|max) ;;
  *)
    echo "--claude-effort must be one of: low, medium, high, max" >&2
    exit 1
    ;;
esac

case "$claude_timeout_seconds" in
  ''|*[!0-9]*|0) echo "--claude-timeout-seconds must be a positive integer" >&2; exit 1 ;;
esac

case "$claude_max_attempts" in
  ''|*[!0-9]*|0) echo "--claude-max-attempts must be a positive integer" >&2; exit 1 ;;
esac

case "$claude_retry_backoff_seconds" in
  ''|*[!0-9]*) echo "--claude-retry-backoff-seconds must be numeric" >&2; exit 1 ;;
esac

case "$openclaw_timeout_seconds" in
  ''|*[!0-9]*|0) echo "--openclaw-timeout-seconds must be a positive integer" >&2; exit 1 ;;
esac

flow_skill_dir="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
profile_home="${profile_home:-$(resolve_flow_profile_registry_root)}"
profiles_dir="${profile_home}"
profile_dir="${profiles_dir}/${profile_id}"
profile_yaml="${profile_dir}/control-plane.yaml"
profile_templates_dir="${profile_dir}/templates"
profile_readme="${profile_dir}/README.md"

base_root="/tmp/agent-control-plane-${profile_id}"
repo_root="${repo_root:-${base_root}/repo}"
agent_repo_root="${agent_repo_root:-${repo_root}}"
agent_root="${agent_root:-${base_root}/runtime/${profile_id}}"
worktree_root="${worktree_root:-${base_root}/worktrees}"
retained_repo_root="${retained_repo_root:-${base_root}/retained}"
vscode_workspace_file="${vscode_workspace_file:-${base_root}/${profile_id}-agents.code-workspace}"

safe_id="${profile_id//-/_}"
issue_prefix="${profile_id}-issue-"
pr_prefix="${profile_id}-pr-"
issue_branch_prefix="agent/${profile_id}/issue"
pr_worktree_branch_prefix="agent/${profile_id}/pr"
managed_pr_branch_globs="agent/${profile_id}/* codex/* openclaw/*"
safe_profile="${safe_id}_safe"
bypass_profile="${safe_id}_bypass"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
runtime_skill_root_hint="~/.agent-runtime/runtime-home/skills/openclaw/agent-control-plane"

if [[ "$force" != "1" ]]; then
  if [[ -e "$profile_yaml" ]]; then
    echo "profile already exists: $profile_yaml" >&2
    exit 1
  fi
fi

mkdir -p "$profile_dir" "$profile_templates_dir"

write_profile_readme() {
  local target_file="${1:?target file required}"
  cat >"$target_file" <<EOF
# ${profile_id} Profile Notes

This file stores repo-specific guidance for the installed ${profile_id} profile.
Update it after scaffolding so operators know the canonical repo roots,
startup docs, commands, and risk notes for this project.

- Repo slug: ${repo_slug}
- Canonical repo root: ${repo_root}
- Agent repo root: ${agent_repo_root}
- Runtime root: ${agent_root}
- Worktree root: ${worktree_root}
- Retained repo root: ${retained_repo_root}
- VS Code workspace: ${vscode_workspace_file}

## Startup Checklist

1. Read the repo-local AGENTS.md and OpenSpec startup docs.
2. Confirm the clean automation baseline and default agent checkout roots.
3. Fill in the repo-specific dev, test, and release commands below.
4. Call out any high-risk surfaces that should force escalation.

## Repo-Specific Commands

Fill in the canonical dev/test commands for ${repo_slug}.

## High-Risk Surfaces

- Fill in production-sensitive or coordination-heavy areas for ${repo_slug}.

## Notes

- Scaffolded by tools/bin/scaffold-profile.sh at ${generated_at}.
- Switch profiles with AGENT_PROJECT_ID=${profile_id} or ACP_PROJECT_ID=${profile_id}.
EOF
}

write_profile_yaml() {
  local target_file="${1:?target file required}"
  cat >"$target_file" <<EOF
schema_version: "1"
id: "${profile_id}"
repo:
  slug: "${repo_slug}"
  root: "${repo_root}"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${agent_root}"
  worktree_root: "${worktree_root}"
  agent_repo_root: "${agent_repo_root}"
  runs_root: "${agent_root}/runs"
  state_root: "${agent_root}/state"
  intake_agent_root: "${agent_root}-intake"
  retained_repo_root: "${retained_repo_root}"
  vscode_workspace_file: "${vscode_workspace_file}"
session_naming:
  issue_prefix: "${issue_prefix}"
  pr_prefix: "${pr_prefix}"
  issue_branch_prefix: "${issue_branch_prefix}"
  pr_worktree_branch_prefix: "${pr_worktree_branch_prefix}"
  managed_pr_branch_globs: "${managed_pr_branch_globs}"
queue:
  source: "github"
  issue_labels:
    ready: "agent-ready"
    running: "agent-running"
    blocked: "agent-blocked"
    heavy: "agent-e2e-heavy"
    exclusive: "agent-exclusive"
  pr_labels:
    automerge: "agent-automerge"
    fix_needed: "agent-repair-queued"
    manual_fix_override: "agent-manual-fix-override"
    double_check_1: "agent-double-check-1/2"
    double_check_2: "agent-double-check-2/2"
    human_review: "agent-human-review"
    exclusive: "agent-exclusive"
limits:
  max_concurrent_workers: 6
  max_concurrent_pr_workers: 4
  max_concurrent_heavy_workers: 1
  max_recurring_issue_workers: 2
  max_concurrent_scheduled_issue_workers: 1
  max_concurrent_scheduled_heavy_workers: 1
  max_concurrent_blocked_recovery_issue_workers: 1
  blocked_recovery_cooldown_seconds: 900
  max_open_agent_prs_for_recurring: 6
  max_launches_per_heartbeat: 6
execution:
  coding_worker: "${coding_worker}"
  provider_quota:
    cooldowns: "300,900,1800,3600"
  safe_profile: "${safe_profile}"
  bypass_profile: "${bypass_profile}"
  claude:
    model: "${claude_model}"
    permission_mode: "${claude_permission_mode}"
    effort: "${claude_effort}"
    timeout_seconds: ${claude_timeout_seconds}
    max_attempts: ${claude_max_attempts}
    retry_backoff_seconds: ${claude_retry_backoff_seconds}
  openclaw:
    model: "${openclaw_model}"
    thinking: "${openclaw_thinking}"
    timeout_seconds: ${openclaw_timeout_seconds}
  ollama:
    model: "qwen2.5-coder:7b"
    base_url: "http://localhost:11434"
    timeout_seconds: 900
  pi:
    model: "openrouter/qwen/qwen3.6-plus:free"
    thinking: "low"
    timeout_seconds: 900
    stall_seconds: 300
  opencode:
    model: "anthropic/claude-sonnet-4-20250514"
    timeout_seconds: 900
  kilo:
    model: "anthropic/claude-sonnet-4-20250514"
    timeout_seconds: 900
  review_requires_independent_final_review: true
  verification:
    web_playwright_command: "pnpm exec playwright test"
  infra_ci_bypass:
    enabled: true
    env_var: "ACP_ALLOW_INFRA_CI_BYPASS"
    scope: "infrastructure-only GitHub Actions failures such as billing or spending-limit job-start failures"
  codex_quota_rotation:
    enabled: true
    strategy: "failure-driven"
    threshold_used_percent: 70
    weekly_threshold_used_percent: 90
    soft_threshold_used_percent: 55
    soft_worker_threshold: 4
    emergency_threshold_used_percent: 65
    emergency_worker_threshold: 6
    switch_cooldown_seconds: 600
    timeout_seconds: 45
    prefer_label_env: "ACP_CODEX_QUOTA_PREFER_LABEL"
  codex_session_recovery:
    enabled: true
    max_resume_attempts: 6
    auth_refresh_timeout_seconds: 900
    auth_refresh_poll_seconds: 10
    recovery_failure_reasons:
      - "usage-limit"
      - "auth-refresh-timeout"
      - "resume-attempts-exhausted"
shared_runtime:
  skill_root_hint: "${runtime_skill_root_hint}"
  capture_worker: "tools/bin/agent-project-capture-worker"
  github_update_labels: "tools/bin/agent-github-update-labels"
  heartbeat_loop: "tools/bin/agent-project-heartbeat-loop"
  run_coding_session: "tools/bin/agent-project-run-codex-session"
  publish_issue_pr: "tools/bin/agent-project-publish-issue-pr"
  reconcile_issue_session: "tools/bin/agent-project-reconcile-issue-session"
  reconcile_pr_session: "tools/bin/agent-project-reconcile-pr-session"
  heartbeat_hooks: "hooks/heartbeat-hooks.sh"
  issue_reconcile_hooks: "hooks/issue-reconcile-hooks.sh"
  pr_reconcile_hooks: "hooks/pr-reconcile-hooks.sh"
adapter_scripts:
  pr_risk: "bin/pr-risk.sh"
  issue_resource_class: "bin/issue-resource-class.sh"
  sync_pr_labels: "bin/sync-pr-labels.sh"
  label_follow_up_issues: "bin/label-follow-up-issues.sh"
scripts:
  capture_worker: "tools/bin/capture-worker.sh"
  heartbeat: "tools/bin/heartbeat-safe-auto.sh"
  heartbeat_preflight: "tools/bin/heartbeat-recovery-preflight.sh"
  start_issue_worker: "tools/bin/start-issue-worker.sh"
  start_pr_review_worker: "tools/bin/start-pr-review-worker.sh"
  start_pr_fix_worker: "tools/bin/start-pr-fix-worker.sh"
  reconcile_issue_worker: "tools/bin/reconcile-issue-worker.sh"
  reconcile_pr_worker: "tools/bin/reconcile-pr-worker.sh"
  retry_state: "tools/bin/retry-state.sh"
  worker_status: "tools/bin/worker-status.sh"
  risk_classifier: "bin/pr-risk.sh"
  label_sync: "bin/sync-pr-labels.sh"
  cleanup_worktree: "tools/bin/cleanup-worktree.sh"
policies:
  escalation:
    - "missing credentials or broken auth"
    - "product decision or unresolved ambiguity"
    - "production deploy or prod-facing release action"
    - "high-risk merge decision"
  critical_infra:
    - "database migrations"
    - "destructive data operations"
    - "deployment scripts or release gates"
  double_check_default:
    - "auth or RBAC"
    - "billing or subscription logic"
    - "shared packages"
    - "repo automation or CI flow changes"
  notes:
    - "Scaffolded by tools/bin/scaffold-profile.sh at ${generated_at}."
    - "Switch profiles with AGENT_PROJECT_ID or ACP_PROJECT_ID."
EOF
}

write_profile_yaml "$profile_yaml"
write_profile_readme "$profile_readme"

if compgen -G "${flow_skill_dir}/tools/templates/*.md" >/dev/null; then
  cp "${flow_skill_dir}"/tools/templates/*.md "$profile_templates_dir"/
fi

profile_home_real="$(mkdir -p "$profile_home" && cd "$profile_home" && pwd -P)"
profile_yaml_real="$(cd "$(dirname "$profile_yaml")" && pwd -P)/$(basename "$profile_yaml")"
profile_templates_dir_real="$(cd "$profile_templates_dir" && pwd -P)"
profile_readme_real="$(cd "$(dirname "$profile_readme")" && pwd -P)/$(basename "$profile_readme")"

printf 'PROFILE_ID=%s\n' "$profile_id"
printf 'PROFILE_HOME=%s\n' "$profile_home_real"
printf 'PROFILE_YAML=%s\n' "$profile_yaml_real"
printf 'PROFILE_TEMPLATE_DIR=%s\n' "$profile_templates_dir_real"
printf 'PROFILE_README=%s\n' "$profile_readme_real"
printf 'REPO_SLUG=%s\n' "$repo_slug"
printf 'CODING_WORKER=%s\n' "$coding_worker"
printf 'NEXT_STEP=ACP_PROJECT_ID=%s bash %s/tools/bin/render-flow-config.sh\n' "$profile_id" "$flow_skill_dir"
printf 'NEXT_STEP=bash %s/tools/bin/sync-shared-agent-home.sh\n' "$flow_skill_dir"
