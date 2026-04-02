#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-resident-worker-lib.sh"

ISSUE_ID="${1:?usage: start-issue-worker.sh ISSUE_ID [safe|bypass]}"
MODE="${2:-safe}"
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "start-issue-worker.sh"; then
  exit 64
fi
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
flow_export_project_env_aliases
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
TEMPLATE_FILE="$(flow_resolve_template_file "issue-prompt-template.md" "${WORKSPACE_DIR}" "${CONFIG_YAML}")"
SCHEDULED_TEMPLATE_FILE="$(flow_resolve_template_file "scheduled-issue-prompt-template.md" "${WORKSPACE_DIR}" "${CONFIG_YAML}")"
LOCAL_INSTALL_POLICY_BIN="${WORKSPACE_DIR}/bin/issue-requires-local-workspace-install.sh"
SESSION="${ISSUE_SESSION_PREFIX}${ISSUE_ID}"
RUN_DIR="${RUNS_ROOT}/${SESSION}"
UPDATE_LABELS_BIN="${WORKSPACE_DIR}/bin/agent-github-update-labels"
CODING_WORKER="${ACP_CODING_WORKER:-${F_LOSNING_CODING_WORKER:-codex}}"
launch_success="no"
label_rollback_armed="no"
RECURRING_CHECKLIST_SYNC_BIN="${FLOW_TOOLS_DIR}/sync-recurring-issue-checklist.sh"

issue_block_and_exit() {
  local comment_body="${1:?comment body required}"
  local comment_marker="${2:?comment marker required}"

  if ! jq -e --arg marker "$comment_marker" 'any(.comments[]?; (.body // "") | contains($marker))' >/dev/null <<<"$ISSUE_JSON"; then
    flow_github_api_repo "$REPO_SLUG" "issues/${ISSUE_ID}/comments" --method POST -f body="$comment_body" >/dev/null 2>&1 || true
  fi
  if [[ -x "${UPDATE_LABELS_BIN}" ]]; then
    bash "${UPDATE_LABELS_BIN}" --repo-slug "${REPO_SLUG}" --number "${ISSUE_ID}" --add agent-blocked --remove agent-running >/dev/null 2>&1 || true
  fi
  label_rollback_armed="no"
  launch_success="yes"
  exit 0
}

rollback_labels_on_failure() {
  if [[ "${label_rollback_armed}" != "yes" || "${launch_success}" == "yes" ]]; then
    return 0
  fi
  if [[ -x "${UPDATE_LABELS_BIN}" ]]; then
    bash "${UPDATE_LABELS_BIN}" --repo-slug "${REPO_SLUG}" --number "${ISSUE_ID}" --remove agent-running >/dev/null 2>&1 || true
  fi
}

recurring_checklist_total="0"
recurring_checklist_unchecked="0"
recurring_checklist_matched_pr_numbers=""

refresh_recurring_issue_from_github() {
  ISSUE_JSON="$(flow_github_issue_view_json "$REPO_SLUG" "$ISSUE_ID")"
  ISSUE_TITLE="$(jq -r '.title' <<<"$ISSUE_JSON")"
  ISSUE_BODY="$(jq -r '.body // ""' <<<"$ISSUE_JSON")"
  ISSUE_URL="$(jq -r '.url' <<<"$ISSUE_JSON")"
  ISSUE_AUTOMERGE="$(jq -r 'if any(.labels[]?; .name == "agent-automerge") then "yes" else "no" end' <<<"$ISSUE_JSON")"
}

refresh_recurring_issue_checklist_state() {
  local sync_out=""

  recurring_checklist_total="0"
  recurring_checklist_unchecked="0"
  recurring_checklist_matched_pr_numbers=""

  [[ "${ISSUE_IS_KEEP_OPEN:-no}" == "yes" ]] || return 0
  [[ -x "${RECURRING_CHECKLIST_SYNC_BIN}" ]] || return 0

  sync_out="$(
    ACP_REPO_ID="${ACP_REPO_ID:-${F_LOSNING_REPO_ID:-}}" \
    bash "${RECURRING_CHECKLIST_SYNC_BIN}" \
      --repo-slug "${REPO_SLUG}" \
      --issue-id "${ISSUE_ID}" 2>/dev/null || true
  )"

  recurring_checklist_total="$(awk -F= '/^CHECKLIST_TOTAL=/{print $2; exit}' <<<"${sync_out}")"
  recurring_checklist_unchecked="$(awk -F= '/^CHECKLIST_UNCHECKED=/{print $2; exit}' <<<"${sync_out}")"
  recurring_checklist_matched_pr_numbers="$(awk -F= '/^CHECKLIST_MATCHED_PR_NUMBERS=/{print $2; exit}' <<<"${sync_out}")"

  case "${recurring_checklist_total}" in
    ''|*[!0-9]*) recurring_checklist_total="0" ;;
  esac
  case "${recurring_checklist_unchecked}" in
    ''|*[!0-9]*) recurring_checklist_unchecked="0" ;;
  esac

  refresh_recurring_issue_from_github
}

block_if_recurring_checklist_complete() {
  [[ "${ISSUE_IS_KEEP_OPEN:-no}" == "yes" ]] || return 0

  refresh_recurring_issue_checklist_state

  if [[ "${recurring_checklist_total}" -gt 0 && "${recurring_checklist_unchecked}" -eq 0 ]]; then
    local blocker_comment=""

    blocker_comment="$(cat <<EOF
# Blocker: All checklist items already completed

All checklist items for issue #${ISSUE_ID} appear to be satisfied on the current baseline.

Why this run was stopped early:
- recurring automation should not spend another worker cycle when every listed improvement is already checked off
- the issue body was refreshed against merged PR history before this decision

Required next step:
- refresh the issue body with new unchecked improvement items before re-queueing this issue
EOF
)"

    if [[ -n "${recurring_checklist_matched_pr_numbers}" ]]; then
      blocker_comment="${blocker_comment}"$'\n\n'"Recently matched PRs: #$(sed 's/,/, #/g' <<<"${recurring_checklist_matched_pr_numbers}")"
    fi

    issue_block_and_exit "${blocker_comment}" "# Blocker: All checklist items already completed"
  fi
}

reap_stale_run_dir() {
  if [[ ! -d "$RUN_DIR" ]]; then
    return 0
  fi
  if [[ -f "$RUN_DIR/run.env" ]]; then
    if grep -q '^RESIDENT_WORKER_ENABLED=yes$' "$RUN_DIR/run.env" 2>/dev/null; then
      if "${FLOW_TOOLS_DIR}/agent-project-archive-run" \
        --runs-root "$RUNS_ROOT" \
        --history-root "$HISTORY_ROOT" \
        --session "$SESSION" >/dev/null 2>&1; then
        return 0
      fi
    fi
    if "${WORKSPACE_DIR}/bin/cleanup-worktree.sh" "" "$SESSION" >/dev/null 2>&1; then
      return 0
    fi
  fi
  mkdir -p "$HISTORY_ROOT"
  mv "$RUN_DIR" "${HISTORY_ROOT}/${SESSION}-stale-$(date +%Y%m%d-%H%M%S)"
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "worker session already exists: $SESSION" >&2
  exit 1
fi

label_rollback_armed="yes"
trap rollback_labels_on_failure EXIT INT TERM

refresh_recurring_issue_from_github
ISSUE_SCHEDULE_INTERVAL_SECONDS="$(
  ISSUE_BODY="$ISSUE_BODY" node <<'EOF'
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
)"
ISSUE_REQUIRES_LOCAL_WORKSPACE_INSTALL="$(
  ISSUE_BODY="$ISSUE_BODY" bash "$LOCAL_INSTALL_POLICY_BIN"
)"
if [[ "${ISSUE_SCHEDULE_INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
  TEMPLATE_FILE="${SCHEDULED_TEMPLATE_FILE}"
fi

ISSUE_IS_KEEP_OPEN="$(jq -r 'if any(.labels[]?; .name == "agent-keep-open") then "yes" else "no" end' <<<"$ISSUE_JSON")"
RESIDENT_WORKER_ENABLED="no"
RESIDENT_WORKER_KEY=""
RESIDENT_WORKER_DIR=""
RESIDENT_WORKER_META_FILE=""
RESIDENT_LANE_KIND=""
RESIDENT_LANE_VALUE=""
RESIDENT_WORKTREE_REUSED="no"
RESIDENT_TASK_COUNT="0"
RESIDENT_OPENCLAW_AGENT_ID=""
RESIDENT_OPENCLAW_SESSION_ID=""
RESIDENT_OPENCLAW_AGENT_DIR=""
RESIDENT_OPENCLAW_STATE_DIR=""
RESIDENT_OPENCLAW_CONFIG_PATH=""
RESIDENT_WORKTREE_REALPATH=""

if flow_resident_issue_backend_supported "${CODING_WORKER}" \
  && flow_is_truthy "$(flow_resident_issue_workers_enabled "${CONFIG_YAML}")" \
  && ( [[ "${ISSUE_IS_KEEP_OPEN}" == "yes" ]] || [[ "${ISSUE_SCHEDULE_INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ ]] ); then
  RESIDENT_WORKER_ENABLED="yes"
  if [[ "${ISSUE_SCHEDULE_INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
    RESIDENT_LANE_KIND="scheduled"
    RESIDENT_LANE_VALUE="${ISSUE_SCHEDULE_INTERVAL_SECONDS}"
  else
    RESIDENT_LANE_KIND="recurring"
    RESIDENT_LANE_VALUE="general"
  fi
  RESIDENT_WORKER_KEY="$(flow_resident_issue_lane_key "${CODING_WORKER}" "${MODE}" "${RESIDENT_LANE_KIND}" "${RESIDENT_LANE_VALUE}")"
  RESIDENT_WORKER_DIR="$(flow_resident_issue_lane_dir "${CONFIG_YAML}" "${RESIDENT_WORKER_KEY}")"
  RESIDENT_WORKER_META_FILE="$(flow_resident_issue_lane_meta_file "${CONFIG_YAML}" "${RESIDENT_WORKER_KEY}")"
  if [[ "${CODING_WORKER}" == "openclaw" ]]; then
    RESIDENT_OPENCLAW_AGENT_ID="$(flow_resident_issue_lane_openclaw_agent_id "${CONFIG_YAML}" "${RESIDENT_WORKER_KEY}")"
    RESIDENT_OPENCLAW_SESSION_ID="$(flow_resident_issue_lane_openclaw_session_id "${CONFIG_YAML}" "${RESIDENT_WORKER_KEY}")"
    RESIDENT_OPENCLAW_AGENT_DIR="${RESIDENT_WORKER_DIR}/openclaw-agent"
    RESIDENT_OPENCLAW_STATE_DIR="${RESIDENT_WORKER_DIR}/openclaw-state"
    RESIDENT_OPENCLAW_CONFIG_PATH="${RESIDENT_WORKER_DIR}/openclaw-config/openclaw.json"
  fi
fi

if [[ -d "$RUN_DIR" ]]; then
  reap_stale_run_dir
fi

block_if_recurring_checklist_complete

mkdir -p "$RUN_DIR"

MISSING_CHANGE_PATHS="$(
  ISSUE_BODY="$ISSUE_BODY" AGENT_REPO_ROOT="$AGENT_REPO_ROOT" node <<'EOF'
const fs = require('fs');
const path = require('path');

const body = process.env.ISSUE_BODY || '';
const repoRoot = process.env.AGENT_REPO_ROOT || '';
const matches = Array.from(body.matchAll(/openspec\/changes\/[A-Za-z0-9._/-]+/g))
  .map((match) => match[0]);
const unique = [...new Set(matches)];
const missing = unique.filter((relativePath) => !fs.existsSync(path.join(repoRoot, relativePath)));
process.stdout.write(missing.join('\n'));
EOF
)"

if [[ -n "$MISSING_CHANGE_PATHS" ]]; then
  missing_bullets="$(printf '%s\n' "$MISSING_CHANGE_PATHS" | sed 's/^/- /')"
  issue_block_and_exit \
"Blocked on missing referenced OpenSpec paths for issue #${ISSUE_ID}.

The issue body points at change-package paths that do not exist in the clean baseline checkout used by automation:
${missing_bullets}

Why this blocks safe implementation:
- the issue is asking automation to follow a planning/change artifact that is not present in the repo baseline
- without a real canonical source, the worker would have to invent scope or requirements

Fastest unblock:
- update the issue to point at existing canonical specs/paths, or
- restore the missing OpenSpec change package before re-queueing this issue." \
    "Blocked on missing referenced OpenSpec paths for issue #${ISSUE_ID}."
fi

ISSUE_RECURRING_CONTEXT_FILE="${RUN_DIR}/issue-recurring-context.md"
ISSUE_JSON="$ISSUE_JSON" REPO_SLUG="$REPO_SLUG" FLOW_CONFIG_LIB_PATH="${SCRIPT_DIR}/flow-config-lib.sh" node <<'EOF' >"$ISSUE_RECURRING_CONTEXT_FILE"
const { execFileSync } = require('child_process');

const issue = JSON.parse(process.env.ISSUE_JSON || '{}');
const repoSlug = process.env.REPO_SLUG || '';
const isRecurring = Array.isArray(issue.labels)
  && issue.labels.some((label) => label && label.name === 'agent-keep-open');

if (!isRecurring) {
  process.exit(0);
}

const prNumbers = [];
for (const comment of issue.comments || []) {
  const body = comment?.body || '';
  for (const match of body.matchAll(/Opened PR #(\d+)/g)) {
    const number = Number(match[1]);
    if (number && !prNumbers.includes(number)) {
      prNumbers.push(number);
    }
  }
}

const recentNumbers = prNumbers.slice(-5).reverse();
const recentPrs = recentNumbers.map((number) => {
  try {
    const raw = execFileSync(
      'bash',
      ['-lc', `source "${process.env.FLOW_CONFIG_LIB_PATH}"; flow_github_pr_view_json "${repoSlug}" "${number}"`],
      { encoding: 'utf8' },
    );
    const pr = JSON.parse(raw);
    return {
      number: pr.number,
      title: pr.title,
      url: pr.url,
      state: pr.isDraft ? 'draft' : String(pr.state || '').toLowerCase(),
    };
  } catch (error) {
    return {
      number,
      title: 'Unable to load PR details',
      url: '',
      state: 'unknown',
    };
  }
});

const activePrs = recentPrs.filter((pr) => pr.state === 'open' || pr.state === 'draft');
const completedPrs = recentPrs.filter((pr) => pr.state !== 'open' && pr.state !== 'draft');

const formatPr = (pr) => {
  const suffix = pr.url ? ` ${pr.url}` : '';
  return `- #${pr.number} (${pr.state}): ${pr.title}${suffix}`;
};

const lines = [
  '',
  '## Recurring Issue Guardrails',
  'Because this issue carries `agent-keep-open`:',
  '- Before editing, choose exactly one concrete target module, screen, or flow and keep the cycle limited to that target.',
  '- Do not work on a target already covered by an open or draft PR for this issue, or by the most recent completed cycles listed below, unless you are explicitly fixing a regression introduced there.',
  '- If you cannot identify a small non-overlapping target after reviewing recent cycle history, stop blocked using the blocker contract instead of forcing another PR.',
  '- In your final worker output, start with `Target:` and `Why now:` lines before the changed-files list.',
];

if (activePrs.length > 0) {
  lines.push('', '### Active PRs to avoid overlapping');
  for (const pr of activePrs) {
    lines.push(formatPr(pr));
  }
}

if (completedPrs.length > 0) {
  lines.push('', '### Most recent completed cycles');
  for (const pr of completedPrs) {
    lines.push(formatPr(pr));
  }
}

process.stdout.write(`${lines.join('\n')}\n`);
EOF
ISSUE_RECURRING_CONTEXT="$(cat "$ISSUE_RECURRING_CONTEXT_FILE")"
ISSUE_RETRY_STATE="$(
  bash "${WORKSPACE_DIR}/bin/retry-state.sh" issue "$ISSUE_ID" get 2>/dev/null || true
)"
ISSUE_BLOCKER_CONTEXT="$(
  ISSUE_JSON="$ISSUE_JSON" ISSUE_RETRY_STATE="$ISSUE_RETRY_STATE" node <<'EOF'
const issue = JSON.parse(process.env.ISSUE_JSON || '{}');
const labels = new Set((issue.labels || []).map((label) => label?.name).filter(Boolean));
const retryState = String(process.env.ISSUE_RETRY_STATE || '');

const retryMap = Object.fromEntries(
  retryState
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const idx = line.indexOf('=');
      if (idx === -1) {
        return [line, ''];
      }
      return [line.slice(0, idx), line.slice(idx + 1)];
    }),
);
const attempts = Number.parseInt(retryMap.ATTEMPTS || '0', 10);
const lastReason = String(retryMap.LAST_REASON || '').trim();
const nextAttemptAt = String(retryMap.NEXT_ATTEMPT_AT || '').trim();

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

const inferCommentReason = (bodyText) => {
  const body = String(bodyText || '');
  const marker = 'Failure reason:';
  const markerIndex = body.search(/Failure reason:/i);
  if (markerIndex !== -1) {
    const backtick = String.fromCharCode(96);
    const tail = body.slice(markerIndex + marker.length);
    const firstQuoted = tail.split(backtick)[1];
    if (firstQuoted) {
      return firstQuoted.trim();
    }
  }
  if (/^# Blocker: Verification requirements were not satisfied$/im.test(body)) {
    return 'verification-guard-blocked';
  }
  if (/^# Blocker: (All checklist items already completed|Worker produced no publishable delta)$/im.test(body)) {
    return 'no-publishable-commits';
  }
  if (/scope guard/i.test(body)) {
    return 'scope-guard-blocked';
  }
  if (/^# Blocker: Provider quota is currently exhausted$/im.test(body)) {
    return 'provider-quota-limit';
  }
  return '';
};

const effectiveLastReason =
  lastReason && lastReason !== 'issue-worker-blocked'
    ? lastReason
    : inferCommentReason(blockerComment?.body || '') || lastReason;

if (!blockerComment || !blockerComment.body) {
  const fallbackLines = [
    '',
    '## Prior Blocker Context',
    'This issue is being retried after an `agent-blocked` stop.',
    '- First resolve the prior blocker instead of repeating the same broad implementation path.',
  ];
  if (effectiveLastReason) {
    fallbackLines.push('- Last recorded blocker: `' + effectiveLastReason + '`.');
  }
  if (attempts > 0) {
    fallbackLines.push('- Blocked retries so far: ' + attempts + '.');
  }
  if (effectiveLastReason === 'scope-guard-blocked' && attempts >= 2) {
    fallbackLines.push(
      '- This issue has already hit the scope guard multiple times. Do not attempt another broad multi-surface patch.',
      `- Either ship one focused slice that stays under the scope guard, or create focused follow-up issues with \`bash "$FLOW_TOOLS_DIR/create-follow-up-issue.sh" --parent ${issue.number} --title "..." --body-file /tmp/follow-up.md\` and supersede the umbrella.`,
    );
  }
  process.stdout.write(fallbackLines.join('\n'));
  process.exit(0);
}

const normalizedBody = String(blockerComment.body).trim();
const clippedBody =
  normalizedBody.length > 1600 ? `${normalizedBody.slice(0, 1600).trimEnd()}\n\n[truncated]` : normalizedBody;

const lines = [
  '',
  '## Prior Blocker Context',
  'This issue is being retried after an `agent-blocked` stop.',
  '- Address the blocker below before attempting a new implementation/publish cycle.',
];

if (effectiveLastReason) {
  lines.push('- Last recorded blocker: `' + effectiveLastReason + '`.');
}
if (attempts > 0) {
  lines.push('- Blocked retries so far: ' + attempts + '.');
}
if (nextAttemptAt) {
  lines.push('- Last scheduled retry target was ' + nextAttemptAt + '.');
}
if (effectiveLastReason === 'scope-guard-blocked') {
  lines.push('- Treat this as a scope problem first: narrow to one safe slice or decompose into focused follow-up issues.');
  if (attempts >= 2) {
    lines.push(`- Because the scope guard has already fired multiple times, do not retry the same umbrella patch. Use \`bash "$FLOW_TOOLS_DIR/create-follow-up-issue.sh" --parent ${issue.number} --title "..." --body-file /tmp/follow-up.md\` for the remaining slices, then supersede the umbrella if you covered the full decomposition.`);
  }
} else if (effectiveLastReason === 'verification-guard-blocked') {
  lines.push('- Add the missing verification or shrink the touched surface before attempting another publish cycle.');
}

lines.push('', clippedBody);
process.stdout.write(lines.join('\n'));
EOF
)"

ISSUE_SLUG="$(printf '%s' "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' | cut -c1-48)"
if [[ -z "$ISSUE_SLUG" ]]; then
  ISSUE_SLUG="issue"
fi

ensure_resident_issue_worktree_alias() {
  local target_worktree=""
  local alias_path=""

  [[ "${RESIDENT_WORKER_ENABLED}" == "yes" ]] || return 0
  [[ -n "${WORKTREE:-}" && -d "${WORKTREE:-}" ]] || return 0
  [[ -n "${RESIDENT_WORKER_DIR:-}" ]] || return 0

  target_worktree="$(cd "${WORKTREE}" && pwd -P)"
  alias_path="${RESIDENT_WORKER_DIR}/worktree"
  mkdir -p "${RESIDENT_WORKER_DIR}"
  rm -rf "${alias_path}" 2>/dev/null || true
  ln -s "${target_worktree}" "${alias_path}"
  WORKTREE="${alias_path}"
  RESIDENT_WORKTREE_REALPATH="${target_worktree}"
}

write_resident_issue_metadata_started() {
  local started_at="${1:?started_at required}"
  local resident_lane_kind="${RESIDENT_LANE_KIND:-}"
  local resident_lane_value="${RESIDENT_LANE_VALUE:-}"
  [[ "${RESIDENT_WORKER_ENABLED}" == "yes" ]] || return 0

  if [[ -z "${resident_lane_kind}" ]]; then
    resident_lane_kind="$(flow_resident_issue_lane_field_from_key "${RESIDENT_WORKER_KEY:-}" kind 2>/dev/null || true)"
  fi
  if [[ -z "${resident_lane_value}" ]]; then
    resident_lane_value="$(flow_resident_issue_lane_field_from_key "${RESIDENT_WORKER_KEY:-}" value 2>/dev/null || true)"
  fi

  flow_resident_write_metadata "${RESIDENT_WORKER_META_FILE}" \
    "RESIDENT_WORKER_KIND=issue" \
    "RESIDENT_WORKER_SCOPE=lane" \
    "RESIDENT_WORKER_KEY=${RESIDENT_WORKER_KEY}" \
    "RESIDENT_LANE_KIND=${resident_lane_kind}" \
    "RESIDENT_LANE_VALUE=${resident_lane_value}" \
    "ISSUE_ID=${ISSUE_ID}" \
    "ADAPTER_ID=$(flow_resolve_adapter_id "${CONFIG_YAML}")" \
    "CODING_WORKER=${CODING_WORKER}" \
    "WORKTREE=${WORKTREE}" \
    "WORKTREE_REALPATH=${RESIDENT_WORKTREE_REALPATH:-${WORKTREE}}" \
    "LAST_BRANCH=${BRANCH}" \
    "OPENCLAW_AGENT_ID=${RESIDENT_OPENCLAW_AGENT_ID}" \
    "OPENCLAW_SESSION_ID=${RESIDENT_OPENCLAW_SESSION_ID}" \
    "OPENCLAW_AGENT_DIR=${RESIDENT_OPENCLAW_AGENT_DIR}" \
    "OPENCLAW_STATE_DIR=${RESIDENT_OPENCLAW_STATE_DIR}" \
    "OPENCLAW_CONFIG_PATH=${RESIDENT_OPENCLAW_CONFIG_PATH}" \
    "TASK_COUNT=${RESIDENT_TASK_COUNT}" \
    "LAST_STARTED_AT=${started_at}" \
    "LAST_FINISHED_AT=${LAST_FINISHED_AT:-}" \
    "LAST_RUN_SESSION=${SESSION}" \
    "LAST_WORKTREE_REUSED=${RESIDENT_WORKTREE_REUSED}" \
    "LAST_STATUS=running"
}

open_or_reuse_issue_worktree() {
  local resident_started_at=""
  local max_tasks=""
  local max_age_seconds=""
  local reuse_output=""
  local current_issue_id="${ISSUE_ID}"
  local current_session="${SESSION}"
  local previous_issue_id=""
  local current_resident_worker_scope="${RESIDENT_WORKER_SCOPE:-lane}"
  local current_resident_worker_key="${RESIDENT_WORKER_KEY}"
  local current_resident_worker_dir="${RESIDENT_WORKER_DIR}"
  local current_resident_worker_meta_file="${RESIDENT_WORKER_META_FILE}"
  local current_resident_lane_kind="${RESIDENT_LANE_KIND}"
  local current_resident_lane_value="${RESIDENT_LANE_VALUE}"
  local current_resident_openclaw_agent_id="${RESIDENT_OPENCLAW_AGENT_ID}"
  local current_resident_openclaw_session_id="${RESIDENT_OPENCLAW_SESSION_ID}"
  local current_resident_openclaw_agent_dir="${RESIDENT_OPENCLAW_AGENT_DIR}"
  local current_resident_openclaw_state_dir="${RESIDENT_OPENCLAW_STATE_DIR}"
  local current_resident_openclaw_config_path="${RESIDENT_OPENCLAW_CONFIG_PATH}"

  if [[ "${RESIDENT_WORKER_ENABLED}" == "yes" ]]; then
    max_tasks="$(flow_resident_issue_worker_max_tasks "${CONFIG_YAML}")"
    max_age_seconds="$(flow_resident_issue_worker_max_age_seconds "${CONFIG_YAML}")"
    if flow_resident_issue_can_reuse "${RESIDENT_WORKER_META_FILE}" "${max_tasks}" "${max_age_seconds}"; then
      set -a
      # shellcheck source=/dev/null
      source "${RESIDENT_WORKER_META_FILE}"
      set +a
      previous_issue_id="${ISSUE_ID:-}"
      ISSUE_ID="${current_issue_id}"
      SESSION="${current_session}"
      RESIDENT_WORKER_SCOPE="${current_resident_worker_scope}"
      RESIDENT_WORKER_KEY="${current_resident_worker_key}"
      RESIDENT_WORKER_DIR="${current_resident_worker_dir}"
      RESIDENT_WORKER_META_FILE="${current_resident_worker_meta_file}"
      RESIDENT_LANE_KIND="${current_resident_lane_kind}"
      RESIDENT_LANE_VALUE="${current_resident_lane_value}"
      RESIDENT_OPENCLAW_AGENT_ID="${current_resident_openclaw_agent_id}"
      RESIDENT_OPENCLAW_SESSION_ID="${current_resident_openclaw_session_id}"
      RESIDENT_OPENCLAW_AGENT_DIR="${current_resident_openclaw_agent_dir}"
      RESIDENT_OPENCLAW_STATE_DIR="${current_resident_openclaw_state_dir}"
      RESIDENT_OPENCLAW_CONFIG_PATH="${current_resident_openclaw_config_path}"
      RESIDENT_TASK_COUNT="$(( ${TASK_COUNT:-0} + 1 ))"
      RESIDENT_WORKTREE_REUSED="yes"
      if [[ "${CODING_WORKER}" == "openclaw" && -n "${previous_issue_id}" && "${previous_issue_id}" != "${current_issue_id}" ]]; then
        # Keep the resident lane's warm workspace/agent files, but rotate the
        # OpenClaw conversation thread when switching issues to reduce context drift.
        RESIDENT_OPENCLAW_SESSION_ID="$(flow_resident_issue_openclaw_session_id "${CONFIG_YAML}" "${current_issue_id}")"
      fi
      if reuse_output="$("${WORKSPACE_DIR}/bin/reuse-issue-worktree.sh" "${WORKTREE}" "${ISSUE_ID}" "${ISSUE_SLUG}" 2>&1)"; then
        WORKTREE_OUT="${reuse_output}"
      else
        printf 'RESIDENT_REUSE_FALLBACK=issue-%s reason=%s\n' "${ISSUE_ID}" "$(printf '%s' "${reuse_output}" | tr '\n' ' ' | sed 's/  */ /g')" >&2
        RESIDENT_TASK_COUNT="1"
        RESIDENT_WORKTREE_REUSED="no"
        if [[ "$ISSUE_REQUIRES_LOCAL_WORKSPACE_INSTALL" == "yes" ]]; then
          WORKTREE_OUT="$(ACP_WORKTREE_LOCAL_INSTALL=true F_LOSNING_WORKTREE_LOCAL_INSTALL=true "${WORKSPACE_DIR}/bin/new-worktree.sh" "$ISSUE_ID" "$ISSUE_SLUG")"
        else
          WORKTREE_OUT="$("${WORKSPACE_DIR}/bin/new-worktree.sh" "$ISSUE_ID" "$ISSUE_SLUG")"
        fi
      fi
    else
      RESIDENT_TASK_COUNT="1"
      RESIDENT_WORKTREE_REUSED="no"
      if [[ "$ISSUE_REQUIRES_LOCAL_WORKSPACE_INSTALL" == "yes" ]]; then
        WORKTREE_OUT="$(ACP_WORKTREE_LOCAL_INSTALL=true F_LOSNING_WORKTREE_LOCAL_INSTALL=true "${WORKSPACE_DIR}/bin/new-worktree.sh" "$ISSUE_ID" "$ISSUE_SLUG")"
      else
        WORKTREE_OUT="$("${WORKSPACE_DIR}/bin/new-worktree.sh" "$ISSUE_ID" "$ISSUE_SLUG")"
      fi
    fi
  else
    if [[ "$ISSUE_REQUIRES_LOCAL_WORKSPACE_INSTALL" == "yes" ]]; then
      WORKTREE_OUT="$(ACP_WORKTREE_LOCAL_INSTALL=true F_LOSNING_WORKTREE_LOCAL_INSTALL=true "${WORKSPACE_DIR}/bin/new-worktree.sh" "$ISSUE_ID" "$ISSUE_SLUG")"
    else
      WORKTREE_OUT="$("${WORKSPACE_DIR}/bin/new-worktree.sh" "$ISSUE_ID" "$ISSUE_SLUG")"
    fi
  fi

  WORKTREE="$(awk -F= '/^WORKTREE=/{print $2}' <<<"$WORKTREE_OUT")"
  BRANCH="$(awk -F= '/^BRANCH=/{print $2}' <<<"$WORKTREE_OUT")"
  ensure_resident_issue_worktree_alias
  ISSUE_BASELINE_HEAD_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"

  if [[ "${RESIDENT_WORKER_ENABLED}" == "yes" ]]; then
    resident_started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_resident_issue_metadata_started "${resident_started_at}"
  fi
}

open_or_reuse_issue_worktree

PROMPT_FILE="${RUN_DIR}/prompt.md"

build_issue_verification_command_snippet() {
  ISSUE_BODY="$ISSUE_BODY" AGENT_REPO_ROOT="$AGENT_REPO_ROOT" node <<'EOF'
const fs = require('fs');
const path = require('path');

const body = String(process.env.ISSUE_BODY || '');
const repoRoot = String(process.env.AGENT_REPO_ROOT || '');
const commands = [];
const seen = new Set();
const backtick = String.fromCharCode(96);

const addCommand = (value) => {
  const command = String(value || '').trim();
  if (!command || seen.has(command)) {
    return;
  }
  seen.add(command);
  commands.push(command);
};

for (const line of body.split(/\r?\n/).slice(0, 40)) {
  if (!/^\s*-\s+/.test(line)) continue;
  if (!/(?:\bRun\b|\balso run\b|\bafter code changes\b|\bevery completed cycle\b)/i.test(line)) continue;
  const matches = line.matchAll(new RegExp(backtick + '([^' + backtick + ']+)' + backtick, 'g'));
  for (const match of matches) {
    addCommand(match[1]);
  }
}

if (commands.length === 0 && repoRoot) {
  const packageJsonPath = path.join(repoRoot, 'package.json');
  if (fs.existsSync(packageJsonPath)) {
    try {
      const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
      if (packageJson?.scripts?.test) {
        if (fs.existsSync(path.join(repoRoot, 'pnpm-lock.yaml'))) {
          addCommand('pnpm test');
        } else if (fs.existsSync(path.join(repoRoot, 'yarn.lock'))) {
          addCommand('yarn test');
        } else {
          addCommand('npm test');
        }
      }
    } catch (_error) {
      // Ignore parse errors and fall through to generic guidance.
    }
  }
}

if (commands.length === 0) {
  addCommand('pnpm test');
}

const escapeDoubleQuotes = (value) => value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
const snippet = commands
  .map((command) =>
    command + '\n' +
    'bash "$ACP_FLOW_TOOLS_DIR/record-verification.sh" --run-dir "$ACP_RUN_DIR" --status pass --command "' +
    escapeDoubleQuotes(command) +
    '"',
  )
  .join('\n\n');

process.stdout.write(snippet);
EOF
}

ISSUE_VERIFICATION_COMMAND_SNIPPET="$(build_issue_verification_command_snippet)"
ISSUE_RESIDENT_CONTEXT=""
if [[ "${RESIDENT_WORKER_ENABLED}" == "yes" ]]; then
  ISSUE_RESIDENT_CONTEXT="$(cat <<EOF

## Resident Worker Context

- This recurring/scheduled issue is running in resident-worker mode for the same issue lane.
- Resident task count for this lane: ${RESIDENT_TASK_COUNT}.
- Worktree reused from a prior cycle: ${RESIDENT_WORKTREE_REUSED}.
- Reuse the saved context to avoid rereading the full repo, but first verify the latest repo state before editing so you do not act on stale assumptions.
- Treat this cycle as one focused slice. Do not reopen broad scope just because prior context is available.
EOF
)"
fi
ISSUE_QUALITY_GUARDRAILS="$(cat <<'EOF'

## Host Quality Guardrails

- Before committing, run `git status --short` and remove unrelated generated files or local bootstrap artifacts so only intended code/test/doc changes remain.
- Do not commit `.agent-session.env`, `.openclaw*`, or incidental lockfile churn unless the issue explicitly changes dependency manifests or package-manager/tooling files.
- If you changed CLI or operator-facing commands, flags, argument parsing, usage/help text, or entrypoint scripts, add/update regression coverage and record at least one direct invocation that exercises the changed path before you commit.
EOF
)"

ISSUE_ID="$ISSUE_ID" \
  ISSUE_TITLE="$ISSUE_TITLE" \
ISSUE_URL="$ISSUE_URL" \
ISSUE_AUTOMERGE="$ISSUE_AUTOMERGE" \
ISSUE_BASELINE_HEAD_SHA="$ISSUE_BASELINE_HEAD_SHA" \
  ISSUE_BODY="$ISSUE_BODY" \
  ISSUE_RECURRING_CONTEXT="$ISSUE_RECURRING_CONTEXT" \
  ISSUE_BLOCKER_CONTEXT="$ISSUE_BLOCKER_CONTEXT" \
  ISSUE_VERIFICATION_COMMAND_SNIPPET="$ISSUE_VERIFICATION_COMMAND_SNIPPET" \
  ISSUE_RESIDENT_CONTEXT="$ISSUE_RESIDENT_CONTEXT" \
  ISSUE_QUALITY_GUARDRAILS="$ISSUE_QUALITY_GUARDRAILS" \
  REPO_SLUG="$REPO_SLUG" \
  TEMPLATE_FILE="$TEMPLATE_FILE" \
  node <<'EOF' >"$PROMPT_FILE"
const fs = require('fs');

const template = fs.readFileSync(process.env.TEMPLATE_FILE, 'utf8');
const replacements = {
  '{ISSUE_ID}': process.env.ISSUE_ID || '',
  '{ISSUE_TITLE}': process.env.ISSUE_TITLE || '',
  '{ISSUE_URL}': process.env.ISSUE_URL || '',
  '{ISSUE_AUTOMERGE}': process.env.ISSUE_AUTOMERGE || 'no',
  '{ISSUE_BASELINE_HEAD_SHA}': process.env.ISSUE_BASELINE_HEAD_SHA || '',
  '{REPO_SLUG}': process.env.REPO_SLUG || '',
  '{ISSUE_BODY}': process.env.ISSUE_BODY || '',
  '{ISSUE_RECURRING_CONTEXT}': process.env.ISSUE_RECURRING_CONTEXT || '',
  '{ISSUE_BLOCKER_CONTEXT}': process.env.ISSUE_BLOCKER_CONTEXT || '',
  '{ISSUE_VERIFICATION_COMMAND_SNIPPET}': process.env.ISSUE_VERIFICATION_COMMAND_SNIPPET || '',
};

let rendered = template;
for (const [key, value] of Object.entries(replacements)) {
  rendered = rendered.split(key).join(value);
}
const addendum = String(process.env.ISSUE_QUALITY_GUARDRAILS || '').trim();
const residentContext = String(process.env.ISSUE_RESIDENT_CONTEXT || '').trim();
const addendumParts = [residentContext, addendum].filter(Boolean);
if (addendumParts.length > 0) {
  rendered = `${rendered.trimEnd()}\n\n${addendumParts.join('\n\n')}\n`;
}
process.stdout.write(rendered);
EOF

launch_issue_worker() {
  local runner="${1:?runner required}"

  ACP_ISSUE_ID="$ISSUE_ID" \
    ACP_ISSUE_URL="$ISSUE_URL" \
    ACP_ISSUE_AUTOMERGE="$ISSUE_AUTOMERGE" \
    ACP_RESIDENT_WORKER_ENABLED="$RESIDENT_WORKER_ENABLED" \
    ACP_RESIDENT_WORKER_SCOPE="lane" \
    ACP_RESIDENT_WORKER_KEY="$RESIDENT_WORKER_KEY" \
    ACP_RESIDENT_WORKER_DIR="$RESIDENT_WORKER_DIR" \
    ACP_RESIDENT_WORKER_META_FILE="$RESIDENT_WORKER_META_FILE" \
    ACP_RESIDENT_LANE_KIND="$RESIDENT_LANE_KIND" \
    ACP_RESIDENT_LANE_VALUE="$RESIDENT_LANE_VALUE" \
    ACP_RESIDENT_TASK_COUNT="$RESIDENT_TASK_COUNT" \
    ACP_RESIDENT_WORKTREE_REUSED="$RESIDENT_WORKTREE_REUSED" \
    ACP_RESIDENT_OPENCLAW_AGENT_ID="$RESIDENT_OPENCLAW_AGENT_ID" \
    ACP_RESIDENT_OPENCLAW_SESSION_ID="$RESIDENT_OPENCLAW_SESSION_ID" \
    ACP_RESIDENT_OPENCLAW_AGENT_DIR="$RESIDENT_OPENCLAW_AGENT_DIR" \
    ACP_RESIDENT_OPENCLAW_STATE_DIR="$RESIDENT_OPENCLAW_STATE_DIR" \
    ACP_RESIDENT_OPENCLAW_CONFIG_PATH="$RESIDENT_OPENCLAW_CONFIG_PATH" \
    F_LOSNING_ISSUE_ID="$ISSUE_ID" \
    F_LOSNING_ISSUE_URL="$ISSUE_URL" \
    F_LOSNING_ISSUE_AUTOMERGE="$ISSUE_AUTOMERGE" \
    F_LOSNING_RESIDENT_WORKER_ENABLED="$RESIDENT_WORKER_ENABLED" \
    F_LOSNING_RESIDENT_WORKER_SCOPE="lane" \
    F_LOSNING_RESIDENT_WORKER_KEY="$RESIDENT_WORKER_KEY" \
    F_LOSNING_RESIDENT_WORKER_DIR="$RESIDENT_WORKER_DIR" \
    F_LOSNING_RESIDENT_WORKER_META_FILE="$RESIDENT_WORKER_META_FILE" \
    F_LOSNING_RESIDENT_LANE_KIND="$RESIDENT_LANE_KIND" \
    F_LOSNING_RESIDENT_LANE_VALUE="$RESIDENT_LANE_VALUE" \
    F_LOSNING_RESIDENT_TASK_COUNT="$RESIDENT_TASK_COUNT" \
    F_LOSNING_RESIDENT_WORKTREE_REUSED="$RESIDENT_WORKTREE_REUSED" \
    F_LOSNING_RESIDENT_OPENCLAW_AGENT_ID="$RESIDENT_OPENCLAW_AGENT_ID" \
    F_LOSNING_RESIDENT_OPENCLAW_SESSION_ID="$RESIDENT_OPENCLAW_SESSION_ID" \
    F_LOSNING_RESIDENT_OPENCLAW_AGENT_DIR="$RESIDENT_OPENCLAW_AGENT_DIR" \
    F_LOSNING_RESIDENT_OPENCLAW_STATE_DIR="$RESIDENT_OPENCLAW_STATE_DIR" \
    F_LOSNING_RESIDENT_OPENCLAW_CONFIG_PATH="$RESIDENT_OPENCLAW_CONFIG_PATH" \
    "$runner" "$SESSION" "$WORKTREE" "$PROMPT_FILE"
}

case "$MODE" in
  safe)
    launch_issue_worker "${WORKSPACE_DIR}/bin/run-codex-safe.sh"
    ;;
  bypass)
    launch_issue_worker "${WORKSPACE_DIR}/bin/run-codex-bypass.sh"
    ;;
  *)
    echo "unknown mode: $MODE" >&2
    exit 1
    ;;
esac

launch_success="yes"

printf 'ISSUE_ID=%s\n' "$ISSUE_ID"
printf 'TITLE=%s\n' "$ISSUE_TITLE"
printf 'URL=%s\n' "$ISSUE_URL"
printf 'AUTOMERGE=%s\n' "$ISSUE_AUTOMERGE"
printf 'SESSION=%s\n' "$SESSION"
printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'BRANCH=%s\n' "$BRANCH"
printf 'PROMPT=%s\n' "$PROMPT_FILE"
