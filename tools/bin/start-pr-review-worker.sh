#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

PR_NUMBER="${1:?usage: start-pr-review-worker.sh PR_NUMBER [safe|bypass]}"
MODE="${2:-safe}"
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "start-pr-review-worker.sh"; then
  exit 64
fi
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
flow_export_project_env_aliases
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
PR_SESSION_PREFIX="$(flow_resolve_pr_session_prefix "${CONFIG_YAML}")"
MANAGED_PR_BRANCH_GLOBS="$(flow_resolve_managed_pr_branch_globs "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
TEMPLATE_FILE="$(flow_resolve_template_file "pr-review-template.md" "${WORKSPACE_DIR}" "${CONFIG_YAML}")"
SESSION="${PR_SESSION_PREFIX}${PR_NUMBER}"
RUN_DIR="${RUNS_ROOT}/${SESSION}"
UPDATE_LABELS_BIN="${WORKSPACE_DIR}/bin/agent-github-update-labels"
launch_success="no"
label_rollback_armed="no"

rollback_labels_on_failure() {
  if [[ "${label_rollback_armed}" != "yes" || "${launch_success}" == "yes" ]]; then
    return 0
  fi
  if [[ -x "${UPDATE_LABELS_BIN}" ]]; then
    bash "${UPDATE_LABELS_BIN}" --repo-slug "${REPO_SLUG}" --number "${PR_NUMBER}" --remove agent-running >/dev/null 2>&1 || true
  fi
}

reap_stale_run_dir() {
  if [[ ! -d "$RUN_DIR" ]]; then
    return 0
  fi
  if [[ -f "$RUN_DIR/run.env" ]]; then
    if "${WORKSPACE_DIR}/bin/cleanup-worktree.sh" "" "$SESSION" >/dev/null 2>&1; then
      return 0
    fi
  fi
  mkdir -p "$HISTORY_ROOT"
  mv "$RUN_DIR" "${HISTORY_ROOT}/${SESSION}-stale-$(date +%Y%m%d-%H%M%S)"
}

is_managed_agent_pr_branch() {
  local head_ref="${1:-}"
  local branch_glob=""
  for branch_glob in ${MANAGED_PR_BRANCH_GLOBS}; do
    case "$head_ref" in
      ${branch_glob}) return 0 ;;
    esac
  done
  return 1
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "worker session already exists: $SESSION" >&2
  exit 1
fi

label_rollback_armed="yes"
trap rollback_labels_on_failure EXIT INT TERM

if [[ -d "$RUN_DIR" ]]; then
  reap_stale_run_dir
fi

PR_JSON="$(flow_github_pr_view_json "$REPO_SLUG" "$PR_NUMBER")"
PR_TITLE="$(jq -r '.title' <<<"$PR_JSON")"
PR_BODY="$(jq -r '.body // ""' <<<"$PR_JSON")"
PR_URL="$(jq -r '.url' <<<"$PR_JSON")"
PR_HEAD_REF="$(jq -r '.headRefName' <<<"$PR_JSON")"
PR_BASE_REF="$(jq -r '.baseRefName' <<<"$PR_JSON")"
PR_MERGE_STATE_STATUS="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$PR_JSON")"
PR_HAS_HANDOFF_LABEL="$(jq -r 'any(.labels[]?; .name == "agent-handoff")' <<<"$PR_JSON")"
PR_HAS_AGENT_STATUS_COMMENT="$(jq -r 'any(.comments[]?; ((.body // "") | test("^## PR (final review blocker|repair worker summary|repair summary|repair update)"; "i")))' <<<"$PR_JSON")"
PR_CHECKS_TEXT="$(jq -r '
  if ((.statusCheckRollup // []) | length) == 0 then
    "- none"
  else
    (.statusCheckRollup // [])
    | map(
        "- "
        + (.name // .context // "unknown-check")
        + ": "
        + (.status // "UNKNOWN")
        + (
            if (.conclusion // "") != "" then
              " / " + .conclusion
            else
              ""
            end
          )
      )
    | join("\n")
  end
' <<<"$PR_JSON")"

if ! is_managed_agent_pr_branch "$PR_HEAD_REF" && [[ "$PR_HAS_HANDOFF_LABEL" != "true" ]] && [[ "$PR_HAS_AGENT_STATUS_COMMENT" != "true" ]]; then
  echo "PR branch is not an agent branch: $PR_HEAD_REF" >&2
  exit 1
fi

RISK_JSON="$("${WORKSPACE_DIR}/bin/pr-risk.sh" "$PR_NUMBER")"
PR_RISK="$(jq -r '.risk' <<<"$RISK_JSON")"
PR_RISK_REASON="$(jq -r '.riskReason' <<<"$RISK_JSON")"
PR_AGENT_LANE="$(jq -r '.agentLane' <<<"$RISK_JSON")"
PR_DOUBLE_CHECK_STAGE="$(jq -r '.currentDoubleCheckStage // 0' <<<"$RISK_JSON")"
PR_LINKED_ISSUE_ID="$(jq -r '.linkedIssueId // ""' <<<"$RISK_JSON")"
PR_CHECKS_BYPASSED="$(jq -r '.checksBypassed // false' <<<"$RISK_JSON")"
PR_FILES_TEXT="$(jq -r '.files[] | "- " + .' <<<"$RISK_JSON")"
PR_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
PR_DEPENDENCY_SOURCE_ROOT="${ACP_DEPENDENCY_SOURCE_ROOT:-${F_LOSNING_DEPENDENCY_SOURCE_ROOT:-$PR_REPO_ROOT}}"

case "$PR_AGENT_LANE" in
  double-check-1)
    PR_REVIEW_STAGE_TEXT="Independent agent double-check 1 of 2. A clean pass should advance this PR to the second review pass, not merge it yet."
    ;;
  double-check-2)
    PR_REVIEW_STAGE_TEXT="Independent agent double-check 2 of 2. Review this PR from scratch again; a clean pass may let host reconcile merge it."
    ;;
  *)
    PR_REVIEW_STAGE_TEXT="Single final agent review before merge."
    ;;
esac

WORKTREE_OUT="$("${WORKSPACE_DIR}/bin/new-pr-worktree.sh" "$PR_NUMBER" "$PR_HEAD_REF")"
WORKTREE="$(awk -F= '/^WORKTREE=/{print $2}' <<<"$WORKTREE_OUT")"

mkdir -p "$RUN_DIR"
PROMPT_FILE="${RUN_DIR}/prompt.md"

PR_NUMBER="$PR_NUMBER" \
PR_TITLE="$PR_TITLE" \
PR_URL="$PR_URL" \
PR_HEAD_REF="$PR_HEAD_REF" \
PR_BASE_REF="$PR_BASE_REF" \
PR_BODY="$PR_BODY" \
PR_RISK="$PR_RISK" \
PR_RISK_REASON="$PR_RISK_REASON" \
PR_AGENT_LANE="$PR_AGENT_LANE" \
PR_DOUBLE_CHECK_STAGE="$PR_DOUBLE_CHECK_STAGE" \
PR_REVIEW_STAGE_TEXT="$PR_REVIEW_STAGE_TEXT" \
PR_LINKED_ISSUE_ID="$PR_LINKED_ISSUE_ID" \
PR_CHECKS_BYPASSED="$PR_CHECKS_BYPASSED" \
PR_MERGE_STATE_STATUS="$PR_MERGE_STATE_STATUS" \
PR_CHECKS_TEXT="$PR_CHECKS_TEXT" \
PR_FILES_TEXT="$PR_FILES_TEXT" \
PR_REPO_ROOT="$PR_REPO_ROOT" \
PR_DEPENDENCY_SOURCE_ROOT="$PR_DEPENDENCY_SOURCE_ROOT" \
REPO_SLUG="$REPO_SLUG" \
TEMPLATE_FILE="$TEMPLATE_FILE" \
node <<'EOF' >"$PROMPT_FILE"
const fs = require('fs');

const template = fs.readFileSync(process.env.TEMPLATE_FILE, 'utf8');
const replacements = {
  '{PR_NUMBER}': process.env.PR_NUMBER || '',
  '{PR_TITLE}': process.env.PR_TITLE || '',
  '{PR_URL}': process.env.PR_URL || '',
  '{PR_HEAD_REF}': process.env.PR_HEAD_REF || '',
  '{PR_BASE_REF}': process.env.PR_BASE_REF || '',
  '{PR_BODY}': process.env.PR_BODY || '',
  '{REPO_SLUG}': process.env.REPO_SLUG || '',
  '{PR_RISK}': process.env.PR_RISK || '',
  '{PR_RISK_REASON}': process.env.PR_RISK_REASON || '',
  '{PR_AGENT_LANE}': process.env.PR_AGENT_LANE || '',
  '{PR_DOUBLE_CHECK_STAGE}': process.env.PR_DOUBLE_CHECK_STAGE || '0',
  '{PR_REVIEW_STAGE_TEXT}': process.env.PR_REVIEW_STAGE_TEXT || '',
  '{PR_LINKED_ISSUE_ID}': process.env.PR_LINKED_ISSUE_ID || '',
  '{PR_CHECKS_BYPASSED}': process.env.PR_CHECKS_BYPASSED || 'false',
  '{PR_MERGE_STATE_STATUS}': process.env.PR_MERGE_STATE_STATUS || '',
  '{PR_CHECKS_TEXT}': process.env.PR_CHECKS_TEXT || '',
  '{PR_FILES_TEXT}': process.env.PR_FILES_TEXT || '',
  '{REPO_ROOT}': process.env.PR_REPO_ROOT || '',
  '{DEPENDENCY_SOURCE_ROOT}': process.env.PR_DEPENDENCY_SOURCE_ROOT || '',
};

let rendered = template;
for (const [key, value] of Object.entries(replacements)) {
  rendered = rendered.split(key).join(value);
}
process.stdout.write(rendered);
EOF

case "$MODE" in
  safe)
    F_LOSNING_PR_NUMBER="$PR_NUMBER" \
      F_LOSNING_PR_URL="$PR_URL" \
      F_LOSNING_PR_HEAD_REF="$PR_HEAD_REF" \
      F_LOSNING_ISSUE_ID="$PR_LINKED_ISSUE_ID" \
      "${WORKSPACE_DIR}/bin/run-codex-safe.sh" "$SESSION" "$WORKTREE" "$PROMPT_FILE"
    ;;
  bypass)
    F_LOSNING_PR_NUMBER="$PR_NUMBER" \
      F_LOSNING_PR_URL="$PR_URL" \
      F_LOSNING_PR_HEAD_REF="$PR_HEAD_REF" \
      F_LOSNING_ISSUE_ID="$PR_LINKED_ISSUE_ID" \
      "${WORKSPACE_DIR}/bin/run-codex-bypass.sh" "$SESSION" "$WORKTREE" "$PROMPT_FILE"
    ;;
  *)
    echo "unknown mode: $MODE" >&2
    exit 1
    ;;
esac

launch_success="yes"

printf 'PR_NUMBER=%s\n' "$PR_NUMBER"
printf 'TITLE=%s\n' "$PR_TITLE"
printf 'URL=%s\n' "$PR_URL"
printf 'HEAD_REF=%s\n' "$PR_HEAD_REF"
printf 'BASE_REF=%s\n' "$PR_BASE_REF"
printf 'LINKED_ISSUE_ID=%s\n' "$PR_LINKED_ISSUE_ID"
printf 'RISK=%s\n' "$PR_RISK"
printf 'RISK_REASON=%s\n' "$PR_RISK_REASON"
printf 'SESSION=%s\n' "$SESSION"
printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'PROMPT=%s\n' "$PROMPT_FILE"
