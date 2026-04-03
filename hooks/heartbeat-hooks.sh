#!/usr/bin/env bash
set -euo pipefail

HOOK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_SCRIPT_DIR}/../tools/bin/flow-config-lib.sh"
# shellcheck source=/dev/null
source "${HOOK_SCRIPT_DIR}/../tools/bin/flow-resident-worker-lib.sh"

FLOW_SKILL_DIR="$(cd "${HOOK_SCRIPT_DIR}/.." && pwd)"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
ADAPTER_BIN_DIR="${FLOW_SKILL_DIR}/bin"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
DETACHED_LAUNCH_BIN="${FLOW_TOOLS_DIR}/agent-project-detached-launch"
RESIDENT_ISSUE_LOOP_BIN="${FLOW_TOOLS_DIR}/start-resident-issue-loop.sh"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
DEFAULT_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
PENDING_LAUNCH_DIR="${ACP_PENDING_LAUNCH_DIR:-${F_LOSNING_PENDING_LAUNCH_DIR:-${STATE_ROOT}/pending-launches}}"
AGENT_PR_PREFIXES_JSON="$(flow_managed_pr_prefixes_json "${CONFIG_YAML}")"
AGENT_PR_ISSUE_CAPTURE_REGEX="$(flow_managed_issue_branch_regex "${CONFIG_YAML}")"
AGENT_PR_HANDOFF_LABEL="${AGENT_PR_HANDOFF_LABEL:-agent-handoff}"
AGENT_EXCLUSIVE_LABEL="${AGENT_EXCLUSIVE_LABEL:-agent-exclusive}"
CODING_WORKER="${ACP_CODING_WORKER:-${F_LOSNING_CODING_WORKER:-codex}}"
HEARTBEAT_ISSUE_JSON_CACHE_DIR="${TMPDIR:-/tmp}/heartbeat-issue-json.$$"

heartbeat_issue_retry_state_file() {
  local issue_id="${1:?issue id required}"
  printf '%s/retries/issues/%s.env\n' "${STATE_ROOT}" "${issue_id}"
}

heartbeat_reason_requires_baseline_change() {
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

heartbeat_current_baseline_head_sha() {
  local head_sha=""
  if [[ -d "${AGENT_REPO_ROOT}" ]]; then
    head_sha="$(git -C "${AGENT_REPO_ROOT}" rev-parse --verify --quiet "origin/${DEFAULT_BRANCH}" 2>/dev/null || true)"
    if [[ -z "${head_sha}" ]]; then
      head_sha="$(git -C "${AGENT_REPO_ROOT}" rev-parse --verify --quiet "${DEFAULT_BRANCH}" 2>/dev/null || true)"
    fi
  fi
  printf '%s\n' "${head_sha}"
}

heartbeat_retry_reason_is_baseline_blocked() {
  local issue_id="${1:?issue id required}"
  local reason="${2:-}"
  local state_file baseline_head current_head

  heartbeat_reason_requires_baseline_change "${reason}" || return 1
  state_file="$(heartbeat_issue_retry_state_file "${issue_id}")"
  [[ -f "${state_file}" ]] || return 1

  baseline_head="$(awk -F= '/^BASELINE_HEAD_SHA=/{print substr($0, index($0, "=") + 1); exit}' "${state_file}" 2>/dev/null | tr -d '\r' || true)"
  [[ -n "${baseline_head}" ]] || return 1
  current_head="$(heartbeat_current_baseline_head_sha)"
  [[ -n "${current_head}" ]] || return 1

  [[ "${baseline_head}" == "${current_head}" ]]
}

heartbeat_issue_json_cached() {
  local issue_id="${1:?issue id required}"
  local cache_file=""
  local issue_json=""

  if [[ ! -d "${HEARTBEAT_ISSUE_JSON_CACHE_DIR}" ]]; then
    mkdir -p "${HEARTBEAT_ISSUE_JSON_CACHE_DIR}"
  fi

  cache_file="${HEARTBEAT_ISSUE_JSON_CACHE_DIR}/${issue_id}.json"
  if [[ -f "${cache_file}" ]]; then
    cat "${cache_file}"
    return 0
  fi

  issue_json="$(flow_github_issue_view_json "$REPO_SLUG" "$issue_id" 2>/dev/null || true)"
  printf '%s' "${issue_json}" >"${cache_file}"
  printf '%s\n' "${issue_json}"
}

heartbeat_open_agent_pr_issue_ids() {
  local pr_issue_ids_json=""
  pr_issue_ids_json="$(
    flow_github_pr_list_json "$REPO_SLUG" open 100 \
      2>/dev/null \
      | jq --argjson agentPrPrefixes "${AGENT_PR_PREFIXES_JSON}" --arg handoffLabel "${AGENT_PR_HANDOFF_LABEL}" --arg branchIssueRegex "${AGENT_PR_ISSUE_CAPTURE_REGEX}" '
        map(
          . as $pr
          | select(
              any($agentPrPrefixes[]; (($pr.headRefName // "") | startswith(.)))
              or any(($pr.labels // [])[]?; .name == $handoffLabel)
              or any(($pr.comments // [])[]?; ((.body // "") | test("^## PR (final review blocker|repair worker summary|repair summary|repair update)"; "i")))
            )
          | [
              (
                $pr.headRefName
                | capture($branchIssueRegex)?
                | .id
              ),
              (
                ($pr.body // "")
                | capture("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\s+#(?<id>[0-9]+)\\b")?
                | .id
              )
            ]
          | .[]
          | select(. != null and . != "")
        )
        | unique
      ' 2>/dev/null || true
  )"

  if [[ -z "${pr_issue_ids_json:-}" ]]; then
    printf '[]\n'
  else
    printf '%s\n' "${pr_issue_ids_json}"
  fi
}

heartbeat_list_ready_issue_ids() {
  local open_agent_pr_issue_ids
  local ready_issue_rows issue_id is_blocked retry_reason
  open_agent_pr_issue_ids="$(heartbeat_open_agent_pr_issue_ids)"

  ready_issue_rows="$(
    flow_github_issue_list_json "$REPO_SLUG" open 100 \
    2>/dev/null \
    | jq -r --argjson openAgentPrIssueIds "${open_agent_pr_issue_ids}" '
        map(select(
          (any(.labels[]?; .name == "agent-running") | not)
          and ((.number | tostring) as $issueId | ($openAgentPrIssueIds | index($issueId) | not))
        ))
        | sort_by(.createdAt, .number)
        | .[]
        | [.number, (any(.labels[]?; .name == "agent-blocked"))]
        | @tsv
      ' 2>/dev/null || true
  )"

  while IFS=$'\t' read -r issue_id is_blocked; do
    [[ -n "${issue_id:-}" ]] || continue

    if [[ "${is_blocked:-false}" == "true" ]]; then
      retry_reason="$(heartbeat_issue_blocked_recovery_reason "$issue_id")"
      if [[ -z "${retry_reason:-}" ]]; then
        continue
      fi
      continue
    fi

    printf '%s\n' "$issue_id"
  done <<<"$ready_issue_rows"
}

heartbeat_list_blocked_recovery_issue_ids() {
  local open_agent_pr_issue_ids
  local blocked_issue_rows issue_id retry_reason
  open_agent_pr_issue_ids="$(heartbeat_open_agent_pr_issue_ids)"

  blocked_issue_rows="$(
    flow_github_issue_list_json "$REPO_SLUG" open 100 \
    2>/dev/null \
    | jq -r --argjson openAgentPrIssueIds "${open_agent_pr_issue_ids}" '
        map(select(
          any(.labels[]?; .name == "agent-blocked")
          and (any(.labels[]?; .name == "agent-running") | not)
          and ((.number | tostring) as $issueId | ($openAgentPrIssueIds | index($issueId) | not))
        ))
        | sort_by(.createdAt, .number)
        | .[].number
      ' 2>/dev/null || true
  )"

  while IFS= read -r issue_id; do
    [[ -n "${issue_id:-}" ]] || continue
    retry_reason="$(heartbeat_issue_blocked_recovery_reason "$issue_id")"
    if [[ -z "${retry_reason:-}" ]]; then
      continue
    fi

    printf '%s\n' "$issue_id"
  done <<<"$blocked_issue_rows"
}

heartbeat_issue_blocked_recovery_reason() {
  local issue_id="${1:?issue id required}"
  local retry_out retry_reason issue_json

  retry_out="$("${FLOW_TOOLS_DIR}/retry-state.sh" issue "$issue_id" get 2>/dev/null || true)"
  retry_reason="$(awk -F= '/^LAST_REASON=/{print $2}' <<<"${retry_out:-}")"
  if [[ -n "${retry_reason:-}" && "${retry_reason}" != "issue-worker-blocked" ]]; then
    if heartbeat_retry_reason_is_baseline_blocked "${issue_id}" "${retry_reason}"; then
      return 0
    fi
    printf '%s\n' "$retry_reason"
    return 0
  fi

  issue_json="$(heartbeat_issue_json_cached "$issue_id")"
  if [[ -z "${issue_json:-}" ]]; then
    return 0
  fi

  ISSUE_JSON="${issue_json}" RETRY_REASON="${retry_reason:-}" node <<'EOF'
const issue = JSON.parse(process.env.ISSUE_JSON || '{}');
const labels = new Set((issue.labels || []).map((label) => label?.name).filter(Boolean));

if (!labels.has('agent-blocked')) {
  process.exit(0);
}

const blockerComment = [...(issue.comments || [])]
  .reverse()
  .find((comment) =>
    /Host-side publish blocked for session|Host-side publish failed for session|Blocked on missing referenced OpenSpec paths for issue|Superseded by focused follow-up issues:|Why it was blocked:|^# Blocker:/i.test(
      comment?.body || '',
    ),
  );

if (!blockerComment || !blockerComment.body) {
  process.exit(0);
}

const body = String(blockerComment.body);
let reason = '';

const explicitFailureReason = body.match(/Failure reason:\s*[\r\n]+-\s*`([^`]+)`/i);
if (explicitFailureReason) {
  reason = explicitFailureReason[1];
} else if (/provider quota is currently exhausted|provider-side rate limit|quota window/i.test(body)) {
  reason = 'provider-quota-limit';
} else if (/no publishable delta|no commits ahead of `?origin\/main`?/i.test(body)) {
  reason = 'no-publishable-delta';
} else if (/scope guard/i.test(body)) {
  reason = 'scope-guard-blocked';
} else if (/verification guard/i.test(body)) {
  reason = 'verification-guard-blocked';
} else if (/localization guard/i.test(body) || /^# Blocker: Localization requirements were not satisfied$/im.test(body)) {
  reason = 'localization-guard-blocked';
} else if (/missing referenced OpenSpec paths/i.test(body)) {
  reason = 'missing-openspec-paths';
} else if (/superseded by focused follow-up issues/i.test(body)) {
  reason = 'superseded-by-follow-ups';
} else if (/^# Blocker:/im.test(body)) {
  reason = 'comment-blocked-recovery';
}

  if (reason) {
    process.stdout.write(`${reason}\n`);
  } else if ((process.env.RETRY_REASON || '').trim()) {
    process.stdout.write(`${String(process.env.RETRY_REASON).trim()}\n`);
  }
EOF
}

heartbeat_list_exclusive_issue_ids() {
  local open_agent_pr_issue_ids
  open_agent_pr_issue_ids="$(heartbeat_open_agent_pr_issue_ids)"

  flow_github_issue_list_json "$REPO_SLUG" open 100 \
    2>/dev/null \
    | jq -r --arg exclusiveLabel "${AGENT_EXCLUSIVE_LABEL}" --argjson openAgentPrIssueIds "${open_agent_pr_issue_ids}" '
        map(select(
          any(.labels[]?; .name == $exclusiveLabel)
          and (any(.labels[]?; .name == "agent-running") | not)
          and (any(.labels[]?; .name == "agent-blocked") | not)
          and ((.number | tostring) as $issueId | ($openAgentPrIssueIds | index($issueId) | not))
        ))
        | sort_by(.createdAt, .number)
        | .[].number
      ' 2>/dev/null || true
}

heartbeat_list_running_issue_ids() {
  flow_github_issue_list_json "$REPO_SLUG" open 100 \
    2>/dev/null \
    | jq -r '
        map(select(any(.labels[]?; .name == "agent-running")))
        | sort_by(.createdAt, .number)
        | .[].number
      ' 2>/dev/null || true
}

heartbeat_list_open_agent_pr_ids() {
  flow_github_pr_list_json "$REPO_SLUG" open 100 \
    2>/dev/null \
    | jq -r --argjson agentPrPrefixes "${AGENT_PR_PREFIXES_JSON}" --arg handoffLabel "${AGENT_PR_HANDOFF_LABEL}" '
        map(select(
          . as $pr
          | (
              any($agentPrPrefixes[]; (($pr.headRefName // "") | startswith(.)))
              or any(($pr.labels // [])[]?; .name == $handoffLabel)
              or any(($pr.comments // [])[]?; ((.body // "") | test("^## PR (final review blocker|repair worker summary|repair summary|repair update)"; "i")))
            )
        ))
        | sort_by(.createdAt)
        | .[].number
      ' 2>/dev/null || true
}

heartbeat_list_exclusive_pr_ids() {
  flow_github_pr_list_json "$REPO_SLUG" open 100 \
    2>/dev/null \
    | jq -r --argjson agentPrPrefixes "${AGENT_PR_PREFIXES_JSON}" --arg handoffLabel "${AGENT_PR_HANDOFF_LABEL}" --arg exclusiveLabel "${AGENT_EXCLUSIVE_LABEL}" '
        map(select(
          . as $pr
          | (
              any($agentPrPrefixes[]; (($pr.headRefName // "") | startswith(.)))
              or any(($pr.labels // [])[]?; .name == $handoffLabel)
              or any(($pr.comments // [])[]?; ((.body // "") | test("^## PR (final review blocker|repair worker summary|repair summary|repair update)"; "i")))
            )
          and any(($pr.labels // [])[]?; .name == $exclusiveLabel)
        ))
        | sort_by(.createdAt)
        | .[].number
      ' 2>/dev/null || true
}

heartbeat_issue_is_heavy() {
  local issue_id="${1:?issue id required}"
  local class_out
  class_out="$("${ADAPTER_BIN_DIR}/issue-resource-class.sh" "$issue_id")"
  awk -F= '/^IS_E2E=/{print $2}' <<<"$class_out"
}

heartbeat_issue_is_recurring() {
  local issue_id="${1:?issue id required}"
  local issue_json
  issue_json="$(heartbeat_issue_json_cached "$issue_id")"
  if [[ -n "$issue_json" ]] && jq -e 'any(.labels[]?; .name == "agent-keep-open")' >/dev/null <<<"$issue_json"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

heartbeat_issue_schedule_interval_seconds() {
  local issue_id="${1:?issue id required}"
  local issue_json issue_body
  issue_json="$(heartbeat_issue_json_cached "$issue_id")"
  if [[ -z "$issue_json" ]]; then
    issue_json='{}'
  fi
  issue_body="$(jq -r '.body // ""' <<<"$issue_json")"
  ISSUE_BODY="$issue_body" node <<'EOF'
const body = process.env.ISSUE_BODY || '';
const match = body.match(/^\s*(?:Agent schedule|Schedule|Cadence)\s*:\s*(?:every\s+)?(\d+)\s*([mhd])\s*$/im);
if (!match) {
  process.stdout.write('0\n');
  process.exit(0);
}
const value = Number(match[1]);
const unit = String(match[2] || '').toLowerCase();
const multiplier = { m: 60, h: 3600, d: 86400 }[unit] || 0;
const seconds = Number.isFinite(value) && value > 0 ? value * multiplier : 0;
process.stdout.write(`${seconds}\n`);
EOF
}

heartbeat_issue_schedule_token() {
  local issue_id="${1:?issue id required}"
  local issue_json issue_body
  issue_json="$(heartbeat_issue_json_cached "$issue_id")"
  if [[ -z "$issue_json" ]]; then
    issue_json='{}'
  fi
  issue_body="$(jq -r '.body // ""' <<<"$issue_json")"
  ISSUE_BODY="$issue_body" node <<'EOF'
const body = process.env.ISSUE_BODY || '';
const match = body.match(/^\s*(?:Agent schedule|Schedule|Cadence)\s*:\s*(?:every\s+)?(\d+)\s*([mhd])\s*$/im);
if (!match) {
  process.stdout.write('\n');
  process.exit(0);
}
process.stdout.write(`${match[1]}${String(match[2] || '').toLowerCase()}\n`);
EOF
}

heartbeat_issue_schedule_label() {
  local issue_id="${1:?issue id required}"
  local token
  token="$(heartbeat_issue_schedule_token "$issue_id")"
  if [[ -n "$token" ]]; then
    printf 'agent-schedule-%s\n' "$token"
  fi
}

heartbeat_issue_is_scheduled() {
  local issue_id="${1:?issue id required}"
  local interval_seconds
  interval_seconds="$(heartbeat_issue_schedule_interval_seconds "$issue_id")"
  if [[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

heartbeat_issue_is_exclusive() {
  local issue_id="${1:?issue id required}"
  local issue_json
  issue_json="$(heartbeat_issue_json_cached "$issue_id")"
  if [[ -n "$issue_json" ]] && jq -e --arg exclusiveLabel "${AGENT_EXCLUSIVE_LABEL}" 'any(.labels[]?; .name == $exclusiveLabel)' >/dev/null <<<"$issue_json"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

heartbeat_pr_is_exclusive() {
  local pr_number="${1:?pr number required}"
  local pr_json
  pr_json="$(flow_github_pr_view_json "$REPO_SLUG" "$pr_number" 2>/dev/null || true)"
  if [[ -n "$pr_json" ]] && jq -e --arg exclusiveLabel "${AGENT_EXCLUSIVE_LABEL}" 'any(.labels[]?; .name == $exclusiveLabel)' >/dev/null <<<"$pr_json"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

heartbeat_sync_pr_labels() {
  local pr_number="${1:?pr number required}"
  "${ADAPTER_BIN_DIR}/sync-pr-labels.sh" "$pr_number"
}

heartbeat_pr_risk_json() {
  local pr_number="${1:?pr number required}"
  "${ADAPTER_BIN_DIR}/pr-risk.sh" "$pr_number"
}

heartbeat_mark_issue_running() {
  local issue_id="${1:?issue id required}"
  local is_heavy="${2:-no}"
  if [[ "$is_heavy" == "yes" ]]; then
    bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$issue_id" --remove agent-ready --remove agent-blocked --add agent-running --add agent-e2e-heavy >/dev/null || true
  else
    bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$issue_id" --remove agent-ready --remove agent-blocked --add agent-running >/dev/null || true
  fi
}

heartbeat_issue_launch_failed() {
  local issue_id="${1:?issue id required}"
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$issue_id" --remove agent-running >/dev/null || true
}

heartbeat_ensure_issue_label_exists() {
  local label_name="${1:?label required}"
  local label_description="${2:-}"
  local label_color="${3:-1D76DB}"
  flow_github_label_create "$REPO_SLUG" "$label_name" "$label_description" "$label_color" >/dev/null 2>&1 || true
}

heartbeat_sync_issue_labels() {
  local issue_id="${1:?issue id required}"
  local issue_json issue_body schedule_token schedule_label label_name
  local -a remove_args=()
  local -a add_args=()
  local -a update_args=()

  issue_json="$(heartbeat_issue_json_cached "$issue_id")"
  if [[ -z "$issue_json" ]]; then
    return 0
  fi

  issue_body="$(jq -r '.body // ""' <<<"$issue_json")"
  while IFS= read -r label_name; do
    [[ -n "$label_name" ]] || continue
    if [[ "$label_name" == agent-schedule-* ]]; then
      remove_args+=(--remove "$label_name")
    fi
  done < <(jq -r '.labels[]?.name // empty' <<<"$issue_json")
  remove_args+=(--remove agent-running --remove agent-blocked --remove agent-scheduled)

  schedule_token="$(
    ISSUE_BODY="$issue_body" node <<'EOF'
const body = process.env.ISSUE_BODY || '';
const match = body.match(/^\s*(?:Agent schedule|Schedule|Cadence)\s*:\s*(?:every\s+)?(\d+)\s*([mhd])\s*$/im);
if (!match) {
  process.stdout.write('\n');
  process.exit(0);
}
process.stdout.write(`${match[1]}${String(match[2] || '').toLowerCase()}\n`);
EOF
  )"

  if [[ -n "$schedule_token" ]]; then
    heartbeat_ensure_issue_label_exists "agent-scheduled" "Recurring scheduled check issue" "5319E7"
    add_args+=(--add agent-scheduled)
    schedule_label="agent-schedule-${schedule_token}"
    if [[ -n "$schedule_label" ]]; then
      heartbeat_ensure_issue_label_exists "$schedule_label" "Scheduled recurring cadence for agent checks" "0E8A16"
      add_args+=(--add "$schedule_label")
    fi
  fi

  update_args=(
    --repo-slug "$REPO_SLUG"
    --number "$issue_id"
  )
  if ((${#remove_args[@]} > 0)); then
    update_args+=("${remove_args[@]}")
  fi
  if ((${#add_args[@]} > 0)); then
    update_args+=("${add_args[@]}")
  fi

  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" "${update_args[@]}" >/dev/null || true
}

heartbeat_issue_uses_resident_loop() {
  local issue_id="${1:?issue id required}"

  if ! flow_resident_issue_backend_supported "${CODING_WORKER}"; then
    printf 'no\n'
    return 0
  fi

  if ! flow_is_truthy "$(flow_resident_issue_workers_enabled "${CONFIG_YAML}")"; then
    printf 'no\n'
    return 0
  fi

  if [[ "$(heartbeat_issue_is_recurring "${issue_id}")" == "yes" || "$(heartbeat_issue_is_scheduled "${issue_id}")" == "yes" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

heartbeat_resident_idle_issue_controller_count() {
  local resident_root controller_file controller_pid controller_state count=0

  resident_root="$(flow_resident_workers_root "${CONFIG_YAML}")"
  for controller_file in "${resident_root}"/issues/*/controller.env; do
    [[ -f "${controller_file}" ]] || continue
    controller_state="$(awk -F= '/^CONTROLLER_STATE=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
    [[ "${controller_state}" == "idle" ]] || continue
    controller_pid="$(awk -F= '/^CONTROLLER_PID=/{print $2; exit}' "${controller_file}" 2>/dev/null | tr -d '"' || true)"
    [[ "${controller_pid}" =~ ^[0-9]+$ ]] || continue
    if kill -0 "${controller_pid}" 2>/dev/null; then
      count=$((count + 1))
    fi
  done

  printf '%s\n' "${count}"
}

heartbeat_issue_resident_lane_kind() {
  local issue_id="${1:?issue id required}"
  local interval_seconds=""

  interval_seconds="$(heartbeat_issue_schedule_interval_seconds "${issue_id}")"
  if [[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'scheduled\n'
  else
    printf 'recurring\n'
  fi
}

heartbeat_issue_resident_lane_value() {
  local issue_id="${1:?issue id required}"
  local interval_seconds=""

  interval_seconds="$(heartbeat_issue_schedule_interval_seconds "${issue_id}")"
  if [[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "${interval_seconds}"
  else
    printf 'general\n'
  fi
}

heartbeat_issue_resident_worker_key() {
  local issue_id="${1:?issue id required}"
  local lane_kind=""
  local lane_value=""

  lane_kind="$(heartbeat_issue_resident_lane_kind "${issue_id}")"
  lane_value="$(heartbeat_issue_resident_lane_value "${issue_id}")"
  flow_resident_issue_lane_key "${CODING_WORKER}" "safe" "${lane_kind}" "${lane_value}"
}

heartbeat_pending_issue_launch_pid() {
  local issue_id="${1:?issue id required}"
  local pending_file pid=""

  pending_file="${PENDING_LAUNCH_DIR}/issue-${issue_id}.pid"
  [[ -f "${pending_file}" ]] || return 1

  pid="$(tr -d '[:space:]' <"${pending_file}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1

  printf '%s\n' "${pid}"
}

heartbeat_pending_resident_lane_launch_issue_id() {
  local issue_id="${1:?issue id required}"
  local worker_key=""
  local pending_file=""
  local candidate_issue_id=""
  local candidate_worker_key=""

  worker_key="$(heartbeat_issue_resident_worker_key "${issue_id}")"
  [[ -n "${worker_key}" ]] || return 1
  [[ -d "${PENDING_LAUNCH_DIR}" ]] || return 1

  for pending_file in "${PENDING_LAUNCH_DIR}"/issue-*.pid; do
    [[ -f "${pending_file}" ]] || continue
    candidate_issue_id="${pending_file##*/issue-}"
    candidate_issue_id="${candidate_issue_id%.pid}"
    [[ -n "${candidate_issue_id}" ]] || continue
    if ! heartbeat_pending_issue_launch_pid "${candidate_issue_id}" >/dev/null 2>&1; then
      rm -f "${pending_file}" 2>/dev/null || true
      continue
    fi
    if [[ "$(heartbeat_issue_uses_resident_loop "${candidate_issue_id}")" != "yes" ]]; then
      continue
    fi
    candidate_worker_key="$(heartbeat_issue_resident_worker_key "${candidate_issue_id}")"
    [[ -n "${candidate_worker_key}" && "${candidate_worker_key}" == "${worker_key}" ]] || continue
    printf '%s\n' "${candidate_issue_id}"
    return 0
  done

  return 1
}

heartbeat_live_issue_controller_for_lane() {
  local issue_id="${1:?issue id required}"
  local worker_key=""

  worker_key="$(heartbeat_issue_resident_worker_key "${issue_id}")"
  flow_resident_live_issue_controller_for_key "${CONFIG_YAML}" "${worker_key}" || return 1
}

heartbeat_enqueue_issue_for_live_resident_lane() {
  local issue_id="${1:?issue id required}"
  local live_controller=""
  local controller_issue_id=""

  live_controller="$(heartbeat_live_issue_controller_for_lane "${issue_id}" || true)"
  [[ -n "${live_controller}" ]] || return 1

  controller_issue_id="$(awk -F= '/^ISSUE_ID=/{print $2; exit}' <<<"${live_controller}")"
  if [[ -n "${controller_issue_id}" && "${controller_issue_id}" == "${issue_id}" ]]; then
    printf 'QUEUE_STATUS=controller-already-active\n'
    printf 'ISSUE_ID=%s\n' "${issue_id}"
    return 0
  fi

  flow_resident_issue_enqueue "${CONFIG_YAML}" "${issue_id}" "heartbeat-live-lane" >/dev/null
}

heartbeat_enqueue_issue_for_resident_controller() {
  local issue_id="${1:?issue id required}"
  local idle_controller_count queue_depth

  idle_controller_count="$(heartbeat_resident_idle_issue_controller_count)"
  [[ "${idle_controller_count}" =~ ^[0-9]+$ ]] || idle_controller_count="0"
  if (( idle_controller_count <= 0 )); then
    return 1
  fi

  queue_depth="$(flow_resident_issue_queue_count "${CONFIG_YAML}")"
  [[ "${queue_depth}" =~ ^[0-9]+$ ]] || queue_depth="0"
  if (( queue_depth >= idle_controller_count )); then
    return 1
  fi

  flow_resident_issue_enqueue "${CONFIG_YAML}" "${issue_id}" "heartbeat" >/dev/null
}

heartbeat_start_issue_worker() {
  local issue_id="${1:?issue id required}"
  local pending_lane_issue_id=""
  if [[ "$(heartbeat_issue_uses_resident_loop "${issue_id}")" == "yes" ]]; then
    if heartbeat_enqueue_issue_for_live_resident_lane "${issue_id}"; then
      printf 'LAUNCH_MODE=resident-lease\n'
      return 0
    fi
    pending_lane_issue_id="$(heartbeat_pending_resident_lane_launch_issue_id "${issue_id}" || true)"
    if [[ -n "${pending_lane_issue_id}" ]]; then
      if [[ "${pending_lane_issue_id}" != "${issue_id}" ]]; then
        flow_resident_issue_enqueue "${CONFIG_YAML}" "${issue_id}" "heartbeat-pending-lane" >/dev/null
      fi
      printf 'LAUNCH_MODE=resident-pending-lane\n'
      return 0
    fi
    if heartbeat_enqueue_issue_for_resident_controller "${issue_id}"; then
      printf 'LAUNCH_MODE=resident-lease\n'
      return 0
    fi
    "${DETACHED_LAUNCH_BIN}" --pending-key "issue-${issue_id}" "issue-${issue_id}" "${RESIDENT_ISSUE_LOOP_BIN}" "$issue_id"
  else
    "${DETACHED_LAUNCH_BIN}" --pending-key "issue-${issue_id}" "issue-${issue_id}" "${FLOW_TOOLS_DIR}/start-issue-worker.sh" "$issue_id"
  fi
}

heartbeat_mark_pr_running() {
  local pr_number="${1:?pr number required}"
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$pr_number" --add agent-running --remove agent-blocked >/dev/null || true
}

heartbeat_clear_pr_running() {
  local pr_number="${1:?pr number required}"
  bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$pr_number" --remove agent-running >/dev/null || true
}

heartbeat_start_pr_review_worker() {
  local pr_number="${1:?pr number required}"
  "${DETACHED_LAUNCH_BIN}" --pending-key "pr-${pr_number}" "pr-review-${pr_number}" "${FLOW_TOOLS_DIR}/start-pr-review-worker.sh" "$pr_number"
}

heartbeat_start_pr_merge_repair_worker() {
  local pr_number="${1:?pr number required}"
  "${DETACHED_LAUNCH_BIN}" --pending-key "pr-${pr_number}" "pr-merge-repair-${pr_number}" "${FLOW_TOOLS_DIR}/start-pr-merge-repair-worker.sh" "$pr_number"
}

heartbeat_start_pr_fix_worker() {
  local pr_number="${1:?pr number required}"
  "${DETACHED_LAUNCH_BIN}" --pending-key "pr-${pr_number}" "pr-fix-${pr_number}" "${FLOW_TOOLS_DIR}/start-pr-fix-worker.sh" "$pr_number"
}

heartbeat_start_pr_ci_refresh() {
  local pr_number="${1:?pr number required}"
  local state_root
  state_root="$(flow_resolve_state_root "${CONFIG_YAML}")"
  local head_sha run_ids run_id rerun_count=0

  head_sha="$(flow_github_api_repo "${REPO_SLUG}" "pulls/${pr_number}" --jq .head.sha)"
  run_ids="$(
    flow_github_api_repo "${REPO_SLUG}" "commits/${head_sha}/check-runs" \
      | jq -r '.check_runs[]
        | select((.conclusion // "") == "failure")
        | (.details_url // "")
        | capture("/actions/runs/(?<id>[0-9]+)")?
        | .id // empty' \
      | sort -u
  )"

  if [[ -z "$run_ids" ]]; then
    printf 'CI_REFRESH_STATUS=no-failed-runs\n'
    return 0
  fi

  while IFS= read -r run_id; do
    [[ -n "$run_id" ]] || continue
    if flow_github_api_repo "${REPO_SLUG}" "actions/runs/${run_id}/rerun-failed-jobs" --method POST >/dev/null 2>&1 \
      || flow_github_api_repo "${REPO_SLUG}" "actions/runs/${run_id}/rerun" --method POST >/dev/null 2>&1; then
      rerun_count=$((rerun_count + 1))
    fi
  done <<<"$run_ids"

  "${FLOW_TOOLS_DIR}/retry-state.sh" pr "$pr_number" schedule "ci-refresh-rerun" >/dev/null || true

  printf 'CI_REFRESH_STATUS=rerun-requested\n'
  printf 'PR_NUMBER=%s\n' "$pr_number"
  printf 'HEAD_SHA=%s\n' "$head_sha"
  printf 'RERUN_COUNT=%s\n' "$rerun_count"
}

heartbeat_reconcile_issue() {
  local session="${1:?session required}"
  "${FLOW_TOOLS_DIR}/reconcile-issue-worker.sh" "$session"
}

heartbeat_reconcile_pr() {
  local session="${1:?session required}"
  "${FLOW_TOOLS_DIR}/reconcile-pr-worker.sh" "$session"
}
