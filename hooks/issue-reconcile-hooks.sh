#!/usr/bin/env bash
set -euo pipefail

HOOK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_SCRIPT_DIR}/../tools/bin/flow-config-lib.sh"

FLOW_SKILL_DIR="$(cd "${HOOK_SCRIPT_DIR}/.." && pwd)"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
ADAPTER_BIN_DIR="${FLOW_SKILL_DIR}/bin"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
DEFAULT_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
BLOCKED_RECOVERY_STATE_DIR="${STATE_ROOT}/blocked-recovery-issues"

issue_kick_scheduler() {
  ACP_PROJECT_ID="${PROFILE_ID}" \
  AGENT_PROJECT_ID="${PROFILE_ID}" \
    "${FLOW_TOOLS_DIR}/kick-scheduler.sh" "${1:-2}" >/dev/null || true
}

issue_clear_blocked_recovery_state() {
  rm -f "${BLOCKED_RECOVERY_STATE_DIR}/${ISSUE_ID}.env" 2>/dev/null || true
}

issue_retry_state_file() {
  printf '%s/retries/issues/%s.env\n' "${STATE_ROOT}" "${ISSUE_ID}"
}

issue_reason_requires_baseline_change() {
  local reason="${1:-}"
  case "${reason}" in
    verification-guard-blocked|no-publishable-commits|no-publishable-delta)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

issue_current_baseline_head_sha() {
  local head_sha=""
  if [[ -d "${AGENT_REPO_ROOT}" ]]; then
    head_sha="$(git -C "${AGENT_REPO_ROOT}" rev-parse --verify --quiet "origin/${DEFAULT_BRANCH}" 2>/dev/null || true)"
    if [[ -z "${head_sha}" ]]; then
      head_sha="$(git -C "${AGENT_REPO_ROOT}" rev-parse --verify --quiet "${DEFAULT_BRANCH}" 2>/dev/null || true)"
    fi
  fi
  printf '%s\n' "${head_sha}"
}

issue_record_retry_baseline_gate() {
  local reason="${1:-}"
  local state_file head_sha tmp_file

  issue_reason_requires_baseline_change "${reason}" || return 0
  state_file="$(issue_retry_state_file)"
  [[ -f "${state_file}" ]] || return 0
  head_sha="$(issue_current_baseline_head_sha)"
  [[ -n "${head_sha}" ]] || return 0

  tmp_file="$(mktemp)"
  grep -v '^BASELINE_HEAD_SHA=' "${state_file}" >"${tmp_file}" || true
  printf 'BASELINE_HEAD_SHA=%s\n' "${head_sha}" >>"${tmp_file}"
  mv "${tmp_file}" "${state_file}"
}

issue_has_schedule_cadence() {
  local issue_json issue_body
  issue_json="$(flow_github_issue_view_json "${REPO_SLUG}" "${ISSUE_ID}" 2>/dev/null || true)"
  issue_body="$(jq -r '.body // ""' <<<"${issue_json:-"{}"}")"
  ISSUE_BODY="$issue_body" node <<'EOF' >/dev/null
const body = process.env.ISSUE_BODY || '';
const match = body.match(/^\s*(?:Agent schedule|Schedule|Cadence)\s*:\s*(?:every\s+)?(\d+)\s*([mhd])\s*$/im);
process.exit(match ? 0 : 1);
EOF
}

issue_scheduled_status_kind() {
  local issue_json issue_title issue_body
  issue_json="$(flow_github_issue_view_json "${REPO_SLUG}" "${ISSUE_ID}" 2>/dev/null || true)"
  issue_title="$(jq -r '.title // ""' <<<"${issue_json:-"{}"}")"
  issue_body="$(jq -r '.body // ""' <<<"${issue_json:-"{}"}")"
  ISSUE_TITLE="$issue_title" ISSUE_BODY="$issue_body" node <<'EOF'
const title = process.env.ISSUE_TITLE || '';
const body = process.env.ISSUE_BODY || '';
const haystack = `${title}\n${body}`.toLowerCase();
if (/\be2e\b|\bsmoke\b|playwright|detox|maestro|automation test|smoke test/.test(haystack)) {
  process.stdout.write('smoke\n');
  process.exit(0);
}
if (/\btypecheck\b|\blint\b|\bunit test\b|\bunit-test\b|\bjest\b|\bvitest\b|\btest suite\b|\bbuild\b|\bci\b/.test(haystack)) {
  process.stdout.write('checks\n');
  process.exit(0);
}
if (/\bhealth\b|\/health\b|prod health|system health/.test(haystack)) {
  process.stdout.write('health\n');
  process.exit(0);
}
process.stdout.write('\n');
EOF
}

issue_ensure_status_label_exists() {
  local label_name="${1:?label required}"
  local label_description="${2:-}"
  local label_color="${3:-1D76DB}"
  flow_github_label_create "$REPO_SLUG" "$label_name" "$label_description" "$label_color" >/dev/null 2>&1 || true
}

issue_update_scheduled_status() {
  local status_kind="${1:?status required}"
  local scheduled_kind ok_label alert_label

  if ! issue_has_schedule_cadence; then
    return 0
  fi
  scheduled_kind="$(issue_scheduled_status_kind)"
  if [[ -z "$scheduled_kind" ]]; then
    return 0
  fi

  case "$scheduled_kind" in
    health)
      ok_label="health-ok"
      alert_label="health-not-ok"
      issue_ensure_status_label_exists "$ok_label" "Latest scheduled health check passed" "0E8A16"
      issue_ensure_status_label_exists "$alert_label" "Latest scheduled health check reported an alert" "B60205"
      ;;
    checks)
      ok_label="checks-ok"
      alert_label="checks-not-ok"
      issue_ensure_status_label_exists "$ok_label" "Latest scheduled verification checks passed" "0E8A16"
      issue_ensure_status_label_exists "$alert_label" "Latest scheduled verification checks reported an alert" "B60205"
      ;;
    smoke)
      ok_label="smoke-ok"
      alert_label="smoke-not-ok"
      issue_ensure_status_label_exists "$ok_label" "Latest scheduled smoke or E2E check passed" "0E8A16"
      issue_ensure_status_label_exists "$alert_label" "Latest scheduled smoke or E2E check reported an alert" "B60205"
      ;;
    *)
      return 0
      ;;
  esac

  case "$status_kind" in
    ok)
      bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" \
        --repo-slug "${REPO_SLUG}" \
        --number "$ISSUE_ID" \
        --remove health-ok \
        --remove health-not-ok \
        --remove checks-ok \
        --remove checks-not-ok \
        --remove smoke-ok \
        --remove smoke-not-ok \
        --add "$ok_label" >/dev/null || true
      ;;
    alert)
      bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" \
        --repo-slug "${REPO_SLUG}" \
        --number "$ISSUE_ID" \
        --remove health-ok \
        --remove health-not-ok \
        --remove checks-ok \
        --remove checks-not-ok \
        --remove smoke-ok \
        --remove smoke-not-ok \
        --add "$alert_label" >/dev/null || true
      ;;
  esac
}

issue_before_success() {
  if issue_has_schedule_cadence; then
    return 0
  fi
  ACP_AGENT_ROOT="${AGENT_ROOT}" ACP_RUNS_ROOT="${RUNS_ROOT}" F_LOSNING_RUNS_ROOT="${RUNS_ROOT}" \
    "${ADAPTER_BIN_DIR}/label-follow-up-issues.sh" "$SESSION" >/dev/null || true
}

issue_before_blocked() {
  if issue_has_schedule_cadence; then
    return 0
  fi
  ACP_AGENT_ROOT="${AGENT_ROOT}" ACP_RUNS_ROOT="${RUNS_ROOT}" F_LOSNING_RUNS_ROOT="${RUNS_ROOT}" \
    "${ADAPTER_BIN_DIR}/label-follow-up-issues.sh" "$SESSION" >/dev/null || true
}

issue_schedule_retry() {
  local reason="${1:?reason required}"
  if issue_has_schedule_cadence; then
    return 0
  fi
  "${FLOW_TOOLS_DIR}/retry-state.sh" issue "$ISSUE_ID" schedule "$reason" >/dev/null || true
  issue_record_retry_baseline_gate "${reason}"
}

issue_mark_ready() {
  issue_clear_blocked_recovery_state
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "${REPO_SLUG}" --number "$ISSUE_ID" --remove agent-running --remove agent-blocked >/dev/null || true
}

issue_clear_retry() {
  issue_clear_blocked_recovery_state
  "${FLOW_TOOLS_DIR}/retry-state.sh" issue "$ISSUE_ID" clear >/dev/null || true
}

issue_publish_extra_args() {
  printf '%s\n' --keep-open-label agent-keep-open
}

issue_remove_running() {
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "${REPO_SLUG}" --number "$ISSUE_ID" --remove agent-running --remove agent-blocked >/dev/null || true
}

issue_mark_blocked() {
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" \
    --repo-slug "${REPO_SLUG}" \
    --number "$ISSUE_ID" \
    --remove agent-running \
    --add agent-blocked >/dev/null || true
}

issue_should_close_as_superseded() {
  local comment_file="${run_dir}/issue-comment.md"
  [[ -s "$comment_file" ]] || return 1
  head -n 1 "$comment_file" | grep -q '^Superseded by focused follow-up issues:'
}

issue_close_as_superseded() {
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "${REPO_SLUG}" --number "$ISSUE_ID" --remove agent-running --remove agent-blocked >/dev/null || true
  flow_github_issue_close "$REPO_SLUG" "$ISSUE_ID" >/dev/null 2>&1 || true
}

issue_after_pr_created() {
  local pr_number="${1:?pr number required}"
  local risk_json
  risk_json="$("${ADAPTER_BIN_DIR}/pr-risk.sh" "$pr_number")"
  if [[ "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" == "true" ]]; then
    bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "${REPO_SLUG}" --number "$pr_number" --add agent-automerge >/dev/null || true
  fi
  issue_kick_scheduler 5
}

issue_after_reconciled() {
  local status="${1:-}"
  local outcome="${2:-}"
  local action="${3:-}"

  if [[ "$status" == "SUCCEEDED" && "$outcome" == "reported" ]]; then
    case "$action" in
      host-comment-scheduled-report)
        issue_update_scheduled_status ok
        ;;
      host-comment-scheduled-alert)
        issue_update_scheduled_status alert
        ;;
    esac
  fi

  issue_kick_scheduler 2
}
