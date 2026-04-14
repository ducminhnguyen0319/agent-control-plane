#!/usr/bin/env bash
set -euo pipefail

PR_NUMBER="${1:?usage: sync-pr-labels.sh PR_NUMBER}"
ADAPTER_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_SKILL_DIR="$(cd "${ADAPTER_BIN_DIR}/.." && pwd)"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
# shellcheck source=/dev/null
source "${FLOW_TOOLS_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"

ensure_label() {
  local name="${1:?name required}"
  local color="${2:?color required}"
  local description="${3:?description required}"
  gh label edit "$name" -R "$REPO_SLUG" --color "$color" --description "$description" >/dev/null 2>&1 \
    || gh label create "$name" -R "$REPO_SLUG" --color "$color" --description "$description" >/dev/null 2>&1 \
    || true
}

ensure_label "agent-repair-queued" "D93F0B" "Agent queued this PR for another automated repair pass before merge"
ensure_label "agent-manual-fix-override" "9A6700" "Manual override: force one more PR repair pass on the current head"
ensure_label "agent-ci-refresh" "FBCA04" "Agent confirmed no branch-local repair is needed; host should rerun failed PR checks before another coding pass"
ensure_label "agent-ci-bypassed" "C2E0C6" "CI failures were classified as infrastructure-only and bypassed by policy for this PR"
ensure_label "agent-double-check-1/2" "B602FF" "PR needs the first independent agent review pass before merge"
ensure_label "agent-double-check-2/2" "7D3CFF" "PR passed one independent agent review and needs the second pass before merge"
ensure_label "agent-human-review" "5319E7" "System-breaking PR such as migrations, destructive data operations, or production release/deploy automation; human review/merge required"
ensure_label "agent-human-approved" "1D76DB" "Human approved a human-review PR; automation may proceed if no newer blockers appear"
ensure_label "agent-handoff" "0052CC" "Manual or non-standard PR explicitly handed off to the agent PR lane"
ensure_label "agent-exclusive" "C2185B" "Exclusive priority item: agent should prioritize it and pause launching unrelated work until it finishes"

risk_json="$("${ADAPTER_BIN_DIR}/pr-risk.sh" "$PR_NUMBER")"
is_managed_by_agent="$(jq -r '.isManagedByAgent' <<<"$risk_json")"
if [[ "$is_managed_by_agent" != "true" ]]; then
  printf 'PR_NUMBER=%s\n' "$PR_NUMBER"
  printf 'SYNC_STATUS=ignored-non-agent-branch\n'
  exit 0
fi

lane="$(jq -r '.agentLane' <<<"$risk_json")"
linked_issue_id="$(jq -r '.linkedIssueId // empty' <<<"$risk_json")"
is_blocked="$(jq -r '.isBlocked' <<<"$risk_json")"
has_manual_fix_override="$(jq -r '.hasManualFixOverride' <<<"$risk_json")"
eligible_for_automerge="$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")"
risk_tier="$(jq -r '.riskTier // .risk' <<<"$risk_json")"
checks_bypassed="$(jq -r '.checksBypassed // false' <<<"$risk_json")"
linked_issue_is_exclusive="false"

if [[ -n "$linked_issue_id" ]]; then
  issue_json="$(gh issue view "$linked_issue_id" -R "$REPO_SLUG" --json labels 2>/dev/null || true)"
  if [[ -n "$issue_json" ]] && jq -e 'any(.labels[]?; .name == "agent-exclusive")' >/dev/null <<<"$issue_json"; then
    linked_issue_is_exclusive="true"
  fi
fi

args=()
if [[ "$is_blocked" == "true" ]]; then
  args+=(--remove agent-automerge --remove agent-repair-queued --remove agent-fix-needed --remove agent-ci-refresh --remove agent-ci-bypassed --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved)
elif [[ "$eligible_for_automerge" == "true" ]]; then
  args+=(--add agent-automerge)
else
  args+=(--remove agent-automerge)
fi

if [[ "$checks_bypassed" == "true" ]]; then
  args+=(--add agent-ci-bypassed)
else
  args+=(--remove agent-ci-bypassed)
fi

if [[ "$linked_issue_is_exclusive" == "true" ]]; then
  args+=(--add agent-exclusive)
fi

if [[ "$is_blocked" != "true" ]]; then
  case "$lane" in
    fix)
      args+=(--add agent-repair-queued --remove agent-fix-needed --remove agent-ci-refresh --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved)
      ;;
    ci-refresh)
      args+=(--add agent-ci-refresh --remove agent-repair-queued --remove agent-fix-needed --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved)
      ;;
    double-check-1)
      args+=(--add agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-repair-queued --remove agent-fix-needed --remove agent-ci-refresh --remove agent-human-review --remove agent-human-approved)
      ;;
    double-check-2)
      args+=(--add agent-double-check-2/2 --remove agent-double-check-1/2 --remove agent-repair-queued --remove agent-fix-needed --remove agent-ci-refresh --remove agent-human-review --remove agent-human-approved)
      ;;
    human-review)
      args+=(--add agent-human-review --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-repair-queued --remove agent-fix-needed --remove agent-ci-refresh)
      ;;
    *)
      args+=(--remove agent-repair-queued --remove agent-fix-needed --remove agent-ci-refresh --remove agent-double-check-1/2 --remove agent-double-check-2/2 --remove agent-human-review --remove agent-human-approved)
      ;;
  esac
fi

bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$PR_NUMBER" "${args[@]}" >/dev/null

if [[ -n "$linked_issue_id" ]]; then
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$linked_issue_id" --remove agent-running >/dev/null || true
fi

printf 'PR_NUMBER=%s\n' "$PR_NUMBER"
printf 'SYNC_STATUS=ok\n'
printf 'RISK=%s\n' "$risk_tier"
printf 'AGENT_LANE=%s\n' "$lane"
printf 'LINKED_ISSUE_ID=%s\n' "$linked_issue_id"
printf 'IS_BLOCKED=%s\n' "$is_blocked"
printf 'MANUAL_FIX_OVERRIDE=%s\n' "$has_manual_fix_override"
