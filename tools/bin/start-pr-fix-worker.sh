#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

PR_NUMBER="${1:?usage: start-pr-fix-worker.sh PR_NUMBER [safe|bypass] [fix|merge-repair]}"
MODE="${2:-safe}"
WORKER_KIND="${3:-fix}"
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "start-pr-fix-worker.sh"; then
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
WEB_PLAYWRIGHT_COMMAND="$(flow_resolve_web_playwright_command "${CONFIG_YAML}")"
SESSION="${PR_SESSION_PREFIX}${PR_NUMBER}"
RUN_DIR="${RUNS_ROOT}/${SESSION}"
UPDATE_LABELS_BIN="${WORKSPACE_DIR}/bin/agent-github-update-labels"
launch_success="no"
label_rollback_armed="no"

rollback_labels_on_failure() {
  if [[ "${label_rollback_armed}" != "yes" || "${launch_success}" == "yes" ]]; then
    return 0
  fi
  if [[ -d "${RUN_DIR}" && ! -f "${RUN_DIR}/run.env" && ! -f "${RUN_DIR}/runner.env" && ! -f "${RUN_DIR}/result.env" ]]; then
    rm -rf "${RUN_DIR}" >/dev/null 2>&1 || true
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

case "$WORKER_KIND" in
  fix)
    TEMPLATE_FILE="$(flow_resolve_template_file "pr-fix-template.md" "${WORKSPACE_DIR}" "${CONFIG_YAML}")"
    ;;
  merge-repair)
    TEMPLATE_FILE="$(flow_resolve_template_file "pr-merge-repair-template.md" "${WORKSPACE_DIR}" "${CONFIG_YAML}")"
    ;;
  *)
    echo "unknown worker kind: $WORKER_KIND" >&2
    exit 1
    ;;
esac

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
PR_LINKED_ISSUE_ID="$(jq -r '.linkedIssueId // ""' <<<"$RISK_JSON")"
PR_FILES_TEXT="$(jq -r '.files[] | "- " + .' <<<"$RISK_JSON")"
PR_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
PR_DEPENDENCY_SOURCE_ROOT="${ACP_DEPENDENCY_SOURCE_ROOT:-${F_LOSNING_DEPENDENCY_SOURCE_ROOT:-$PR_REPO_ROOT}}"
render_pr_context_reads_text() {
  local repo_root="${1:?repo root required}"
  local -a candidate_paths=(
    "${repo_root}/AGENTS.md"
    "${repo_root}/openspec/AGENT_RULES.md"
    "${repo_root}/openspec/AGENTS.md"
    "${repo_root}/openspec/project.md"
    "${repo_root}/openspec/CONVENTIONS.md"
    "${repo_root}/docs/TESTING_AND_SEED_POLICY.md"
  )
  local -a existing_paths=()
  local candidate_path=""

  for candidate_path in "${candidate_paths[@]}"; do
    if [[ -f "${candidate_path}" ]]; then
      existing_paths+=("${candidate_path}")
    fi
  done

  if [[ "${#existing_paths[@]}" -eq 0 ]]; then
    printf '%s\n' '- No repo-specific context files were found under the expected AGENTS/OpenSpec/testing-doc locations; rely on the current diff and nearby source.'
    return 0
  fi

  printf '%s\n' "${existing_paths[@]}" | sed 's/^/- `/' | sed 's/$/`/'
}

PR_CONTEXT_READS_TEXT="$(render_pr_context_reads_text "${PR_REPO_ROOT}")"
PR_CHECK_FAILURES_TEXT="$(jq -r '(.checkFailures + .pendingChecks)[]? | "- " + .' <<<"$RISK_JSON")"
if [[ -z "$PR_CHECK_FAILURES_TEXT" ]]; then
  PR_CHECK_FAILURES_TEXT="- none reported"
fi
PR_MISSING_REASONS_TEXT="$(jq -r '.missingReasons[]? | "- " + .' <<<"$RISK_JSON")"
if [[ -z "$PR_MISSING_REASONS_TEXT" ]]; then
  PR_MISSING_REASONS_TEXT="- none"
fi
PR_PULL_JSON="$(flow_github_api_repo "${REPO_SLUG}" "pulls/${PR_NUMBER}" 2>/dev/null || printf '{}\n')"
PR_HEAD_SHA="$(jq -r '.head.sha // .headRefOid // ""' <<<"$PR_PULL_JSON")"
PR_MERGEABLE_STATUS="$(jq -r 'if .mergeable == null then "UNKNOWN" else (.mergeable | tostring | ascii_upcase) end' <<<"$PR_PULL_JSON" 2>/dev/null || printf 'UNKNOWN\n')"

pr_comments_json() {
  local review_route="pulls/${PR_NUMBER}/comments"
  local issue_route="issues/${PR_NUMBER}/comments"
  local payload=""

  if flow_using_gitea; then
    payload="$(flow_github_api_repo "${REPO_SLUG}" "${issue_route}" 2>/dev/null || true)"
  else
    payload="$(flow_github_api_repo "${REPO_SLUG}" "${review_route}" 2>/dev/null || true)"
  fi

  if jq -e 'type == "array"' >/dev/null 2>&1 <<<"${payload}"; then
    printf '%s\n' "${payload}"
    return 0
  fi

  printf '[]\n'
}

pr_issue_comments_json() {
  local payload=""
  payload="$(flow_github_api_repo "${REPO_SLUG}" "issues/${PR_NUMBER}/comments" 2>/dev/null || true)"
  if jq -e 'type == "array"' >/dev/null 2>&1 <<<"${payload}"; then
    printf '%s\n' "${payload}"
    return 0
  fi
  printf '[]\n'
}

PR_REVIEW_FINDINGS_TEXT="$(
  pr_comments_json \
    | jq -r --arg head_sha "$PR_HEAD_SHA" '
        map(select(
          (.user.login == "chatgpt-codex-connector[bot]")
          and (.body | length > 0)
          and ((.commit_id // "") == $head_sha)
        ))
        | if length == 0 then
            "- none"
          else
            map(
              "- " +
              (.path // "unknown-path") +
              (if .line then ":" + (.line | tostring) else "" end) +
              " | " +
              ((.body // "") | gsub("\\s+"; " ") | sub("^\\*\\*<sub><sub>!\\[[^\\]]+\\]\\([^)]*\\)</sub></sub>\\s*"; "") | .)
            )
            | join("\n")
          end
      '
)"
PR_BLOCKER_SUMMARY_TEXT="$(
  pr_issue_comments_json \
    | jq -r '
        map(select((.body // "") | startswith("## PR final review blocker")))
        | if length == 0 then
            "- none"
          else
            (.[-1].body // "")
          end
      '
)"

latest_history_artifact_content() {
  local artifact_name="${1:?artifact name required}"
  local artifact_path=""

  while IFS= read -r artifact_path; do
    [[ -n "$artifact_path" ]] || continue
    if [[ -f "$artifact_path" ]]; then
      cat "$artifact_path"
      return 0
    fi
  done < <(find "$HISTORY_ROOT" -maxdepth 2 -type f -path "${HISTORY_ROOT}/${SESSION}-*/${artifact_name}" | sort -r)

  printf '%s\n' "- none"
}

PR_LOCAL_HOST_BLOCKER_SUMMARY_TEXT="$(latest_history_artifact_content "host-blocker.md")"

WORKTREE_OUT="$("${WORKSPACE_DIR}/bin/new-pr-worktree.sh" "$PR_NUMBER" "$PR_HEAD_REF")"
WORKTREE="$(awk -F= '/^WORKTREE=/{print $2}' <<<"$WORKTREE_OUT")"
PR_BASE_REMOTE="$(flow_resolve_forge_primary_remote "${WORKTREE}" "${REPO_SLUG}" 2>/dev/null || true)"
if [[ -z "${PR_BASE_REMOTE}" ]]; then
  PR_BASE_REMOTE="origin"
fi
PR_BASE_TRACKING_REF="${PR_BASE_REMOTE}/${PR_BASE_REF}"
PR_HOST_MERGE_STATUS="not-applicable"
PR_HOST_MERGE_SUMMARY_TEXT="- not-applicable"

materialize_host_merge_repair() {
  local merge_output=""
  if merge_output="$(git -C "$WORKTREE" merge --no-commit --no-ff "${PR_BASE_TRACKING_REF}" 2>&1)"; then
    PR_HOST_MERGE_STATUS="clean"
    if [[ -n "$merge_output" ]]; then
      PR_HOST_MERGE_SUMMARY_TEXT="$(printf '%s\n' "$merge_output")"
    else
      PR_HOST_MERGE_SUMMARY_TEXT="- host prepared merge state cleanly with no unresolved conflicts"
    fi
    return 0
  fi

  if git -C "$WORKTREE" ls-files -u | grep -q .; then
    PR_HOST_MERGE_STATUS="conflicted"
    if [[ -n "$merge_output" ]]; then
      PR_HOST_MERGE_SUMMARY_TEXT="$(printf '%s\n' "$merge_output")"
    else
      PR_HOST_MERGE_SUMMARY_TEXT="- host prepared merge state with unresolved conflicts"
    fi
    return 0
  fi

  if git -C "$WORKTREE" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    git -C "$WORKTREE" merge --abort >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$merge_output" >&2
  return 1
}

if [[ "$WORKER_KIND" == "merge-repair" ]]; then
  materialize_host_merge_repair
  PR_CONFLICT_PATHS_TEXT="$(
    unresolved_paths="$(git -C "$WORKTREE" diff --name-only --diff-filter=U 2>/dev/null || true)"
    if [[ -n "$unresolved_paths" ]]; then
      printf '%s\n' "$unresolved_paths" | sed 's/^/- /'
    else
      printf '%s\n' "- none detected after host merge preparation"
    fi
  )"
else
  PR_CONFLICT_PATHS_TEXT="$(
    (
      cd "$WORKTREE"
      base_sha="$(git merge-base HEAD "${PR_BASE_TRACKING_REF}" 2>/dev/null || true)"
      if [[ -z "$base_sha" ]]; then
        printf '%s\n' "- unable to compute merge-base"
        exit 0
      fi

      conflict_paths="$(
        git merge-tree "$base_sha" HEAD "${PR_BASE_TRACKING_REF}" \
          | awk '
              /^changed in both$/ { capture=1; next }
              capture && /^(  base|  our|  their)  / {
                path=$NF
                if (!(path in seen)) {
                  seen[path]=1
                  print path
                }
              }
              capture && /^@@ / { capture=0 }
            '
      )"

      if [[ -n "$conflict_paths" ]]; then
        printf '%s\n' "$conflict_paths" | sed 's/^/- /'
      else
        printf '%s\n' "- none detected"
      fi
    ) 2>/dev/null
  )"
fi

if [[ -z "$PR_CONFLICT_PATHS_TEXT" ]]; then
  PR_CONFLICT_PATHS_TEXT="- none detected"
fi

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
PR_LINKED_ISSUE_ID="$PR_LINKED_ISSUE_ID" \
PR_MERGE_STATE_STATUS="$PR_MERGE_STATE_STATUS" \
PR_MERGEABLE_STATUS="$PR_MERGEABLE_STATUS" \
PR_CHECKS_TEXT="$PR_CHECKS_TEXT" \
PR_FILES_TEXT="$PR_FILES_TEXT" \
PR_CONTEXT_READS_TEXT="$PR_CONTEXT_READS_TEXT" \
PR_CHECK_FAILURES_TEXT="$PR_CHECK_FAILURES_TEXT" \
PR_MISSING_REASONS_TEXT="$PR_MISSING_REASONS_TEXT" \
PR_REVIEW_FINDINGS_TEXT="$PR_REVIEW_FINDINGS_TEXT" \
PR_BLOCKER_SUMMARY_TEXT="$PR_BLOCKER_SUMMARY_TEXT" \
PR_LOCAL_HOST_BLOCKER_SUMMARY_TEXT="$PR_LOCAL_HOST_BLOCKER_SUMMARY_TEXT" \
PR_CONFLICT_PATHS_TEXT="$PR_CONFLICT_PATHS_TEXT" \
PR_HOST_MERGE_STATUS="$PR_HOST_MERGE_STATUS" \
PR_HOST_MERGE_SUMMARY_TEXT="$PR_HOST_MERGE_SUMMARY_TEXT" \
PR_REPO_ROOT="$PR_REPO_ROOT" \
PR_DEPENDENCY_SOURCE_ROOT="$PR_DEPENDENCY_SOURCE_ROOT" \
PR_WORKTREE="$WORKTREE" \
PR_BASE_TRACKING_REF="$PR_BASE_TRACKING_REF" \
PR_WEB_PLAYWRIGHT_COMMAND="$WEB_PLAYWRIGHT_COMMAND" \
REPO_SLUG="$REPO_SLUG" \
TEMPLATE_FILE="$TEMPLATE_FILE" \
node <<'EOF' >"$PROMPT_FILE"
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const template = fs.readFileSync(process.env.TEMPLATE_FILE, 'utf8');
const normalizePath = (value) => String(value || '').replace(/\\/g, '/');
const stripCodeExtension = (value) => normalizePath(value).replace(/\.[cm]?[jt]sx?$/i, '');
const stripTestSuffix = (value) => stripCodeExtension(value).replace(/\.(spec|test)$/i, '');
const lastPathSegments = (value, count = 2) => {
  const parts = normalizePath(value).split('/').filter(Boolean);
  return parts.slice(-count).join('/');
};
const isTestFile = (value) =>
  /(?:^|\/)__tests__\//.test(value) ||
  /(?:^|\/)e2e\//.test(value) ||
  /\.(?:spec|test)\.[cm]?[jt]sx?$/i.test(value);
const unique = (values) => [...new Set(values.filter(Boolean))];

let requiredTargetedVerificationText = '- none';
let preApprovedVerificationFallbacksText = '- none';
try {
  const worktree = process.env.PR_WORKTREE || '';
  const baseTrackingRef = process.env.PR_BASE_TRACKING_REF || `origin/${process.env.PR_BASE_REF || 'main'}`;
  if (worktree) {
    const changedFiles = execFileSync(
      'git',
      ['-C', worktree, 'diff', '--name-only', '--diff-filter=ACMR', `${baseTrackingRef}...HEAD`],
      { encoding: 'utf8' },
    )
      .split('\n')
      .map((file) => normalizePath(file).trim())
      .filter(Boolean);

    const changedTestFiles = changedFiles.filter(isTestFile);
    if (changedTestFiles.length > 0) {
      requiredTargetedVerificationText = changedTestFiles
        .map((file) => {
          const anchors = unique([
            stripCodeExtension(lastPathSegments(file, 2)),
            stripCodeExtension(path.basename(file)),
            path.basename(stripTestSuffix(file)),
          ]);
          const hints = anchors.map((anchor) => `\`${anchor}\``);
          if (/(?:^|\/)e2e\//.test(file)) {
            hints.push('scoped `playwright` command');
          } else if (/^apps\/mobile\//.test(file)) {
            hints.push('scoped `detox` or `maestro` command');
          }
          return `- ${file} | accepted command anchors: ${hints.join(', ')}`;
        })
        .join('\n');
    }

    const changedWebE2EFiles = changedFiles.filter((file) =>
      /^apps\/web\/e2e\/.+\.(?:spec|test)\.[cm]?[jt]sx?$/i.test(file),
    );
    if (changedWebE2EFiles.length > 0) {
      preApprovedVerificationFallbacksText = changedWebE2EFiles
        .map((file) => {
          const relativeSpecPath = normalizePath(file).replace(/^apps\/web\//, '');
          const loopbackCommand = [
            'E2E_WEB_SERVER_COMMAND="pnpm exec next dev --hostname 127.0.0.1 --port 3001"',
            'E2E_BASE_URL="http://127.0.0.1:3001"',
            'bash scripts/with-test-namespace.sh',
            process.env.PR_WEB_PLAYWRIGHT_COMMAND || 'pnpm exec playwright test',
            relativeSpecPath,
            '--project=chromium',
          ].join(' ');
          return `- ${file} | loopback retry command: \`${loopbackCommand}\``;
        })
        .join('\n');
    }
  }
} catch (error) {
  requiredTargetedVerificationText =
    '- unable to derive targeted verification coverage automatically; inspect changed test files manually';
  preApprovedVerificationFallbacksText =
    '- unable to derive pre-approved verification fallbacks automatically; inspect changed e2e files manually';
}

const replacements = {
  '{PR_NUMBER}': process.env.PR_NUMBER || '',
  '{PR_TITLE}': process.env.PR_TITLE || '',
  '{PR_URL}': process.env.PR_URL || '',
  '{PR_HEAD_REF}': process.env.PR_HEAD_REF || '',
  '{PR_BASE_REF}': process.env.PR_BASE_REF || '',
  '{PR_BASE_TRACKING_REF}': process.env.PR_BASE_TRACKING_REF || '',
  '{PR_BODY}': process.env.PR_BODY || '',
  '{REPO_SLUG}': process.env.REPO_SLUG || '',
  '{PR_RISK}': process.env.PR_RISK || '',
  '{PR_RISK_REASON}': process.env.PR_RISK_REASON || '',
  '{PR_LINKED_ISSUE_ID}': process.env.PR_LINKED_ISSUE_ID || '',
  '{PR_MERGE_STATE_STATUS}': process.env.PR_MERGE_STATE_STATUS || '',
  '{PR_MERGEABLE_STATUS}': process.env.PR_MERGEABLE_STATUS || '',
  '{PR_CHECKS_TEXT}': process.env.PR_CHECKS_TEXT || '',
  '{PR_FILES_TEXT}': process.env.PR_FILES_TEXT || '',
  '{PR_CONTEXT_READS_TEXT}': process.env.PR_CONTEXT_READS_TEXT || '',
  '{PR_CHECK_FAILURES_TEXT}': process.env.PR_CHECK_FAILURES_TEXT || '',
  '{PR_MISSING_REASONS_TEXT}': process.env.PR_MISSING_REASONS_TEXT || '',
  '{PR_REVIEW_FINDINGS_TEXT}': process.env.PR_REVIEW_FINDINGS_TEXT || '',
  '{PR_BLOCKER_SUMMARY_TEXT}': process.env.PR_BLOCKER_SUMMARY_TEXT || '',
  '{PR_LOCAL_HOST_BLOCKER_SUMMARY_TEXT}': process.env.PR_LOCAL_HOST_BLOCKER_SUMMARY_TEXT || '',
  '{PR_CONFLICT_PATHS_TEXT}': process.env.PR_CONFLICT_PATHS_TEXT || '',
  '{PR_HOST_MERGE_STATUS}': process.env.PR_HOST_MERGE_STATUS || '',
  '{PR_HOST_MERGE_SUMMARY_TEXT}': process.env.PR_HOST_MERGE_SUMMARY_TEXT || '',
  '{REPO_ROOT}': process.env.PR_REPO_ROOT || '',
  '{DEPENDENCY_SOURCE_ROOT}': process.env.PR_DEPENDENCY_SOURCE_ROOT || '',
  '{PR_REQUIRED_TARGETED_VERIFICATION_TEXT}': requiredTargetedVerificationText,
  '{PR_PREAPPROVED_VERIFICATION_FALLBACKS_TEXT}': preApprovedVerificationFallbacksText,
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
printf 'WORKER_KIND=%s\n' "$WORKER_KIND"
printf 'SESSION=%s\n' "$SESSION"
printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'PROMPT=%s\n' "$PROMPT_FILE"
