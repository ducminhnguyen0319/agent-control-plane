#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../tools/bin/flow-config-lib.sh"

PR_NUMBER="${1:?usage: pr-risk.sh PR_NUMBER}"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
MANAGED_PR_PREFIXES_JSON="$(flow_managed_pr_prefixes_json "${CONFIG_YAML}")"
MANAGED_PR_ISSUE_CAPTURE_REGEX="$(flow_managed_issue_branch_regex "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
ALLOW_INFRA_CI_BYPASS="${ACP_ALLOW_INFRA_CI_BYPASS:-1}"
LOCAL_FIRST_PR_POLICY="${ACP_LOCAL_FIRST_PR_POLICY:-1}"
PR_LANE_OVERRIDE_FILE="${STATE_ROOT}/pr-lane-overrides/${PR_NUMBER}.env"
PR_LANE_OVERRIDE=""

if [[ -f "${PR_LANE_OVERRIDE_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${PR_LANE_OVERRIDE_FILE}" || true
fi

gh_api_json_matching_or_fallback() {
  local fallback="${1:?fallback required}"
  local jq_filter="${2:?jq filter required}"
  shift 2
  local output=""

  output="$(gh api "$@" 2>/dev/null || true)"
  if jq -e "${jq_filter}" >/dev/null 2>&1 <<<"${output}"; then
    printf '%s\n' "${output}"
    return 0
  fi

  printf '%s\n' "${fallback}"
}

PR_JSON="$(gh pr view "$PR_NUMBER" -R "$REPO_SLUG" --json number,title,url,body,isDraft,headRefName,headRefOid,baseRefName,labels,files,mergeStateStatus,reviewDecision,reviewRequests,statusCheckRollup,comments)"
PR_HEAD_SHA="$(jq -r '.headRefOid // ""' <<<"$PR_JSON")"
PR_HEAD_COMMITTED_AT=""
if [[ -n "${PR_HEAD_SHA}" ]]; then
  PR_HEAD_COMMITTED_AT="$(gh api "repos/${REPO_SLUG}/commits/${PR_HEAD_SHA}" --jq .commit.committer.date 2>/dev/null || true)"
fi
REVIEW_COMMENTS_JSON="$(gh_api_json_matching_or_fallback '[]' 'type == "array"' "repos/${REPO_SLUG}/pulls/${PR_NUMBER}/comments")"
CHECK_RUNS_JSON='{"check_runs":[]}'
if [[ -n "${PR_HEAD_SHA}" ]]; then
  CHECK_RUNS_JSON="$(gh_api_json_matching_or_fallback '{"check_runs":[]}' 'type == "object" and ((.check_runs // []) | type == "array")' "repos/${REPO_SLUG}/commits/${PR_HEAD_SHA}/check-runs")"
fi

PR_JSON="$PR_JSON" PR_HEAD_SHA="$PR_HEAD_SHA" PR_HEAD_COMMITTED_AT="$PR_HEAD_COMMITTED_AT" REVIEW_COMMENTS_JSON="$REVIEW_COMMENTS_JSON" CHECK_RUNS_JSON="$CHECK_RUNS_JSON" PR_LANE_OVERRIDE="${PR_LANE_OVERRIDE:-}" MANAGED_PR_PREFIXES_JSON="$MANAGED_PR_PREFIXES_JSON" MANAGED_PR_ISSUE_CAPTURE_REGEX="$MANAGED_PR_ISSUE_CAPTURE_REGEX" ALLOW_INFRA_CI_BYPASS="$ALLOW_INFRA_CI_BYPASS" LOCAL_FIRST_PR_POLICY="$LOCAL_FIRST_PR_POLICY" node <<'EOF'
const { execFileSync } = require('node:child_process');
const data = JSON.parse(process.env.PR_JSON);
const reviewComments = JSON.parse(process.env.REVIEW_COMMENTS_JSON || '[]');
const checkRunsPayload = JSON.parse(process.env.CHECK_RUNS_JSON || '{"check_runs":[]}');
const checkRuns = checkRunsPayload.check_runs || [];
const files = (data.files || []).map((file) => file.path);
const labelNames = (data.labels || []).map((label) => label.name);
const comments = data.comments || [];
const reviewRequests = data.reviewRequests || [];
const checks = data.statusCheckRollup || [];
const headRefName = String(data.headRefName || '');
const headSha = String(process.env.PR_HEAD_SHA || '');
const headCommittedAt = String(process.env.PR_HEAD_COMMITTED_AT || '');
const allowInfraCiBypass = String(process.env.ALLOW_INFRA_CI_BYPASS || '1') !== '0';
const localFirstVerificationPolicy = String(process.env.LOCAL_FIRST_PR_POLICY || '1') !== '0';
const handoffLabelName = 'agent-handoff';
const managedBranchPrefixes = JSON.parse(process.env.MANAGED_PR_PREFIXES_JSON || '[]');
const managedIssueBranchRegex = new RegExp(
  String(process.env.MANAGED_PR_ISSUE_CAPTURE_REGEX || '^(?!)$')
);
const isAgentBranch = managedBranchPrefixes.some((prefix) => headRefName.startsWith(prefix));
const hasAgentHandoffLabel = labelNames.includes(handoffLabelName);
const title = String(data.title || '');
const laneOverride = String(process.env.PR_LANE_OVERRIDE || '').trim();
const isBlocked = labelNames.includes('agent-blocked');
const hasRepairQueuedLabel = labelNames.includes('agent-repair-queued');
const hasManualFixNeededLabel = labelNames.includes('agent-fix-needed');
const hasManualFixOverrideLabel = labelNames.includes('agent-manual-fix-override');
const hasHumanApprovedLabel = labelNames.includes('agent-human-approved');
const hasDoubleCheckStageOneLabel = labelNames.includes('agent-double-check-1/2');
const hasDoubleCheckStageTwoLabel = labelNames.includes('agent-double-check-2/2');
const actionableReviewComments = reviewComments.filter((comment) => {
  const login = String(comment?.user?.login || '');
  const commitId = String(comment?.commit_id || '');
  const body = String(comment?.body || '').trim();
  if (login !== 'chatgpt-codex-connector[bot]') return false;
  if (body.length === 0) return false;
  if (headSha && commitId && commitId !== headSha) return false;
  return true;
});
const hasActionableReviewComments = actionableReviewComments.length > 0;

const toTimestamp = (value) => {
  const timestamp = Date.parse(String(value || ''));
  return Number.isFinite(timestamp) ? timestamp : null;
};

const headCommittedAtTs = toTimestamp(headCommittedAt);
const statusComments = comments.filter((comment) =>
  /^## PR (final review blocker|repair worker summary|repair summary|repair update)/i.test(
    String(comment?.body || '').trim(),
  ),
);
const currentHeadStatusComments = headCommittedAtTs === null
  ? statusComments
  : statusComments.filter((comment) => {
      const createdAtTs = toTimestamp(comment?.createdAt);
      if (createdAtTs === null) return true;
      return createdAtTs >= headCommittedAtTs;
    });
const hasAgentStatusComment = statusComments.length > 0;
const isManagedByAgent = isAgentBranch || hasAgentHandoffLabel || hasAgentStatusComment;

const isLowRiskPath = (filePath) => {
  if (/^packages\/i18n\/src\/resources\/[^/]+\.json$/.test(filePath)) return true;
  if (/^docs\/.+/.test(filePath)) return true;
  if (/^[^/]+\.md$/.test(filePath)) return true;
  return false;
};

const isDocPath = (filePath) =>
  /^openspec\//.test(filePath) ||
  /^docs\/.+/.test(filePath) ||
  /(?:^|\/)README\.md$/i.test(filePath) ||
  /^[^/]+\.md$/i.test(filePath);

const isTestPath = (filePath) =>
  /(?:^|\/)__tests__\//.test(filePath) ||
  /(?:^|\/)e2e\//.test(filePath) ||
  /\.(?:spec|test)\.[cm]?[jt]sx?$/.test(filePath);

const isLocaleResourcePath = (filePath) =>
  /^packages\/i18n\/src\/resources\/[^/]+\.json$/.test(filePath);

const isProductNonTestPath = (filePath) =>
  !isDocPath(filePath) &&
  !isTestPath(filePath) &&
  !isLocaleResourcePath(filePath) &&
  (/^apps\//.test(filePath) || /^packages\//.test(filePath));

const isMobileRoutePath = (filePath) =>
  /^apps\/mobile\/app\/.+\.[cm]?[jt]sx?$/.test(filePath) &&
  !isTestPath(filePath);

const mobileSurfaceKey = (filePath) => {
  const relative = filePath
    .replace(/^apps\/mobile\/app\//, '')
    .replace(/\.[cm]?[jt]sx?$/, '');
  const segments = relative
    .split('/')
    .filter(Boolean)
    .filter((segment) => !/^\(.+\)$/.test(segment));
  return segments[0] || relative;
};

const isAuthCriticalScopePath = (filePath) => {
  if (/^apps\/api\/src\/modules\/auth\//.test(filePath)) return true;
  if (filePath === 'apps/api/src/entities/user.entity.ts') return true;
  if (/^apps\/api\/src\/migrations\/.*(?:Email|Phone|Auth|User).*\.[cm]?[jt]s$/.test(filePath))
    return true;
  if (/^apps\/api\/src\/common\/utils\/(?:phone|tenant|email|auth)[^/]*\.[cm]?[jt]s$/.test(filePath))
    return true;
  return false;
};

const isAuthAdjacentScopePath = (filePath) => {
  if (isAuthCriticalScopePath(filePath)) return true;
  if (/^apps\/web\/src\/app\/\(auth\)\//.test(filePath)) return true;
  if (/^apps\/api\/src\/modules\/organization\//.test(filePath)) return true;
  return false;
};

const isMobileRegressionPath = (filePath) => {
  if (/^apps\/mobile\/src\/__tests__\/.+/.test(filePath)) return true;
  if (/^apps\/mobile\/src\/lib\/[^/]+\.spec\.ts$/.test(filePath)) return true;
  if (/^apps\/mobile\/app\/profile\/edit\.tsx$/.test(filePath)) return true;
  if (/^apps\/mobile\/app\/settings\/security\.tsx$/.test(filePath)) return true;
  return false;
};

const isMobileRegressionPr =
  /^test\(mobile\):/i.test(title) &&
  files.length > 0 &&
  files.every((filePath) => isLowRiskPath(filePath) || isMobileRegressionPath(filePath));

const isCriticalInfraPath = (filePath) => {
  if (/^apps\/api\/src\/migrations\//.test(filePath) || /\.sql$/i.test(filePath)) return true;
  if (/^apps\/api\/src\/.*seed[^/]*\.ts$/i.test(filePath)) return true;
  if (/^apps\/api\/SEEDING\.md$/.test(filePath)) return true;
  if (/^docs\/TESTING_AND_SEED_POLICY\.md$/.test(filePath)) return true;
  if (/^\.github\/workflows\//.test(filePath)) return true;
  if (/^(package\.json|pnpm-lock\.yaml|pnpm-workspace\.yaml|turbo\.json)$/.test(filePath)) return true;
  if (/^scripts\//.test(filePath)) return true;
  return false;
};

const isSystemBreakingPath = (filePath) => {
  if (/^apps\/api\/src\/migrations\//.test(filePath) || /\.sql$/i.test(filePath)) return true;
  if (/^apps\/api\/src\/.*seed[^/]*\.ts$/i.test(filePath)) return true;
  if (/^\.github\/workflows\/(?:release|deploy|go-live|production|hotfix|ship|ios|android)/i.test(filePath)) return true;
  if (/^scripts\/(?:release|deploy|go-live|production|rollback|seed|reseed|reset|migrate)/i.test(filePath)) return true;
  return false;
};

const isCriticalAppPath = (filePath) => {
  if (/^apps\/api\/src\/modules\/auth\//.test(filePath)) return true;
  if (/^apps\/api\/src\/modules\/subscription\//.test(filePath)) return true;
  if (/^apps\/api\/src\/common\/decorators\/current-org\.decorator\.ts$/.test(filePath)) return true;
  if (/^apps\/api\/src\/common\/services\/effective-organization-context\.service\.ts$/.test(filePath)) return true;
  return false;
};

const disallowed = files.filter((filePath) => {
  if (isLowRiskPath(filePath)) return false;
  if (isMobileRegressionPr && isMobileRegressionPath(filePath)) return false;
  return true;
});
const criticalInfraFiles = files.filter((filePath) => isCriticalInfraPath(filePath));
const criticalAppFiles = files.filter((filePath) => !criticalInfraFiles.includes(filePath) && isCriticalAppPath(filePath));
const systemBreakingFiles = criticalInfraFiles.filter((filePath) => isSystemBreakingPath(filePath));
const productNonTestFiles = files.filter((filePath) => isProductNonTestPath(filePath));
const mobileProductFiles = productNonTestFiles.filter((filePath) => /^apps\/mobile\//.test(filePath));
const localeResourceFiles = files.filter((filePath) => isLocaleResourcePath(filePath));
const mobileRouteFiles = productNonTestFiles.filter((filePath) => isMobileRoutePath(filePath));
const mobileSurfaceCount = new Set(mobileRouteFiles.map((filePath) => mobileSurfaceKey(filePath))).size;
const authCriticalTouched = productNonTestFiles.some((filePath) => isAuthCriticalScopePath(filePath));
const authMixedScopeFiles = authCriticalTouched
  ? productNonTestFiles.filter((filePath) => !isAuthAdjacentScopePath(filePath))
  : [];
const scopeSplitReasons = [];
if (productNonTestFiles.length > 14) {
  scopeSplitReasons.push(`product_non_test_count=${productNonTestFiles.length} exceeds max=14`);
}
if (mobileProductFiles.length > 8) {
  scopeSplitReasons.push(`mobile_product_count=${mobileProductFiles.length} exceeds max=8`);
}
if (localeResourceFiles.length > 8 && productNonTestFiles.length >= 6) {
  scopeSplitReasons.push(
    `locale_resource_count=${localeResourceFiles.length} with product_non_test_count=${productNonTestFiles.length} exceeds mixed-scope limit`,
  );
}
if (mobileRouteFiles.length > 3) {
  scopeSplitReasons.push(`mobile_route_file_count=${mobileRouteFiles.length} exceeds max=3`);
}
if (mobileSurfaceCount > 2) {
  scopeSplitReasons.push(`mobile_surface_count=${mobileSurfaceCount} exceeds max=2`);
}
if (authMixedScopeFiles.length > 0) {
  scopeSplitReasons.push(
    `auth_mixed_scope_count=${authMixedScopeFiles.length} requires a dedicated auth slice`,
  );
}
const scopeTooBroad = scopeSplitReasons.length > 0;
const riskTier =
  criticalInfraFiles.length > 0
    ? 'critical-infra'
    : criticalAppFiles.length > 0
      ? 'critical-app'
      : disallowed.length === 0
        ? 'low'
        : 'high';
const riskReason =
  riskTier === 'low'
    ? isMobileRegressionPr
      ? 'file-scope-within-low-risk-mobile-regression-allowlist'
      : 'file-scope-within-low-risk-allowlist'
    : riskTier === 'critical-infra'
      ? `paths-within-critical-infra-allowlist:${criticalInfraFiles.join(',')}`
      : riskTier === 'critical-app'
        ? `paths-within-critical-app-allowlist:${criticalAppFiles.join(',')}`
        : `paths-outside-low-risk-allowlist:${disallowed.join(',')}`;

const normalizeRollupCheck = (check) => {
  const typename = String(check?.__typename || '');
  if (typename === 'StatusContext') {
    const name = String(check?.context || 'status-context');
    const state = String(check?.state || '').toUpperCase();
    return {
      name,
      status: state === 'SUCCESS' || state === 'FAILURE' || state === 'ERROR' ? 'COMPLETED' : state,
      conclusion: state === 'SUCCESS' ? 'SUCCESS' : state === 'FAILURE' || state === 'ERROR' ? 'FAILURE' : '',
      reasonField: 'state',
      rawStatus: String(check?.state || '').toLowerCase() || 'unknown',
    };
  }

  return {
    name: String(check?.name || check?.workflowName || 'check-run'),
    status: String(check?.status || '').toUpperCase(),
    conclusion: String(check?.conclusion || '').toUpperCase(),
    reasonField: 'status',
    rawStatus: String(check?.status || '').toLowerCase() || 'unknown',
  };
};

const pendingChecks = [];
const checkFailures = [];
for (const rawCheck of checks) {
  const check = normalizeRollupCheck(rawCheck);
  if (check.status !== 'COMPLETED') {
    pendingChecks.push(`${check.name}:${check.reasonField}-${check.rawStatus}`);
    continue;
  }
  if (check.conclusion !== 'SUCCESS' && check.conclusion !== 'SKIPPED') {
    checkFailures.push(`${check.name}:conclusion-${String(check.conclusion || '').toLowerCase() || 'unknown'}`);
  }
}

const failingCheckRuns = checkRuns.filter((checkRun) => {
  const status = String(checkRun.status || '').toUpperCase();
  const conclusion = String(checkRun.conclusion || '').toUpperCase();
  return status === 'COMPLETED' && conclusion !== 'SUCCESS' && conclusion !== 'SKIPPED';
});

const infraOnlyMessagePatterns = [
  /recent account payments have failed/i,
  /spending limit needs to be increased/i,
  /job was not started because/i,
  /billing\s*&\s*plans/i,
  /exceeded (your )?spending limit/i,
];

function fetchCheckRunAnnotationMessages(checkRun) {
  const annotationsUrl = String(checkRun?.output?.annotations_url || '');
  const annotationsCount = Number(checkRun?.output?.annotations_count || 0);
  if (!annotationsUrl || !Number.isFinite(annotationsCount) || annotationsCount <= 0) {
    return [];
  }

  try {
    const raw = execFileSync('gh', ['api', annotationsUrl], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const annotations = JSON.parse(raw || '[]');
    return annotations
      .map((annotation) => String(annotation?.message || '').trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

const failingCheckRunMessages = failingCheckRuns.flatMap((checkRun) => fetchCheckRunAnnotationMessages(checkRun));
const hasInfraOnlyCheckFailures =
  allowInfraCiBypass &&
  checkFailures.length > 0 &&
  failingCheckRuns.length > 0 &&
  failingCheckRunMessages.length > 0 &&
  failingCheckRunMessages.every((message) => infraOnlyMessagePatterns.some((pattern) => pattern.test(message)));

const effectiveCheckFailures = hasInfraOnlyCheckFailures ? [] : checkFailures;

const mergeStateStatus = String(data.mergeStateStatus || '').toUpperCase();
const hasCleanMergeState = mergeStateStatus === 'CLEAN';
const hasEffectiveCleanMergeState =
  hasCleanMergeState ||
  (hasInfraOnlyCheckFailures && (mergeStateStatus === 'UNSTABLE' || mergeStateStatus === 'UNKNOWN'));
const noChecksReported = checks.length === 0;
const checksOk = pendingChecks.length === 0 && checkFailures.length === 0;
const effectiveChecksOk = pendingChecks.length === 0 && effectiveCheckFailures.length === 0;
const noChecksNeutralForManagedPr = localFirstVerificationPolicy && isManagedByAgent;
const latestAgentStatusComment = [...currentHeadStatusComments].reverse()[0];
const latestAgentStatusBody = String(latestAgentStatusComment?.body || '');
const latestAgentStatusIsBlocker = /^## PR final review blocker/i.test(latestAgentStatusBody);
const latestAgentStatusHasHostGuard =
  /(^|\n)## PR repair host guard/i.test(latestAgentStatusBody) ||
  /Host rejected this repair and did not push it/i.test(latestAgentStatusBody);
const latestAgentStatusIsCiOnlyBlocker =
  latestAgentStatusIsBlocker &&
  (
    /required verification is not green/i.test(latestAgentStatusBody) ||
    /GitHub check [`'"]?Quality Lite[`'"]? is currently [`'"]?COMPLETED\s*\/\s*FAILURE/i.test(latestAgentStatusBody) ||
    /PR merge state is [`'"]?UNSTABLE[`'"]?/i.test(latestAgentStatusBody) ||
    /PR merge state is [`'"]?UNKNOWN[`'"]?/i.test(latestAgentStatusBody) ||
    /merge-safe state/i.test(latestAgentStatusBody)
  ) &&
  !/`(?:apps|packages|openspec|docs|scripts|\.github)\//.test(latestAgentStatusBody);
const latestAgentStatusIsRepairSummary =
  /^## PR repair (worker summary|summary|update)/i.test(latestAgentStatusBody) &&
  !latestAgentStatusHasHostGuard;
const hasOutstandingAgentStatusBlocker =
  latestAgentStatusHasHostGuard ||
  (latestAgentStatusIsBlocker && !latestAgentStatusIsCiOnlyBlocker);
const latestRepairSummaryComment = [...currentHeadStatusComments]
  .reverse()
  .find((comment) => /^## PR repair (worker summary|summary|update)/i.test(String(comment?.body || '').trim()));
const latestRepairSummaryBody = String(latestRepairSummaryComment?.body || '');
const hasNoopRepairSummary =
  latestRepairSummaryBody.length > 0 &&
  (
    /already addressed on the current PR head/i.test(latestRepairSummaryBody) ||
    /already contains the review fix/i.test(latestRepairSummaryBody) ||
    /already satisfy those findings/i.test(latestRepairSummaryBody) ||
    /stale PR review\/check metadata/i.test(latestRepairSummaryBody) ||
    /blocked by the local test environment/i.test(latestRepairSummaryBody) ||
    /external workspace\/node_modules baseline issue/i.test(latestRepairSummaryBody) ||
    /no source change was needed/i.test(latestRepairSummaryBody) ||
    /no source change was made/i.test(latestRepairSummaryBody) ||
    /no branch-local source change was needed/i.test(latestRepairSummaryBody) ||
    /no (additional )?(repository|repo|branch|source) change was needed/i.test(latestRepairSummaryBody) ||
    /no code changes? were made/i.test(latestRepairSummaryBody) ||
    /the reported final-review blocker does not reproduce/i.test(latestRepairSummaryBody) ||
    /already fixed on the current PR (branch|head)/i.test(latestRepairSummaryBody) ||
    /blocked by .*worktree.*dependency/i.test(latestRepairSummaryBody) ||
    /dependency provisioning\s*\/\s*module-link state/i.test(latestRepairSummaryBody) ||
    /this worktree'?s dependency state/i.test(latestRepairSummaryBody)
  );
const hasOutstandingNoopRepairSummary = latestAgentStatusIsRepairSummary && hasNoopRepairSummary;
const shouldCiRefresh =
  hasOutstandingNoopRepairSummary &&
  effectiveCheckFailures.length > 0 &&
  !hasActionableReviewComments &&
  !data.isDraft;
const hasManualFixOverride = hasManualFixOverrideLabel;
const currentDoubleCheckStage =
  (hasDoubleCheckStageTwoLabel || laneOverride === 'double-check-2')
    ? 2
    : (hasDoubleCheckStageOneLabel || laneOverride === 'double-check-1')
      ? 1
      : 0;
const requiresHumanReviewOnCiBypass =
  hasInfraOnlyCheckFailures &&
  systemBreakingFiles.length > 0;
const requiresExplicitHumanApproval =
  systemBreakingFiles.length > 0 || requiresHumanReviewOnCiBypass;
const requiresAgentDoubleCheck =
  !requiresExplicitHumanApproval &&
  (riskTier === 'critical-infra' || riskTier === 'critical-app');

const missingReasons = [];
if (data.isDraft) missingReasons.push('draft');
if (reviewRequests.length > 0) missingReasons.push('requested-reviewers-present');
if (hasOutstandingAgentStatusBlocker) missingReasons.push('agent-status-blocker-present');
if (scopeTooBroad) missingReasons.push('scope-too-broad');
if (hasManualFixOverride) missingReasons.push('manual-fix-override');
if (hasActionableReviewComments && !hasOutstandingNoopRepairSummary) missingReasons.push('review-feedback-present');
if (requiresExplicitHumanApproval && !hasHumanApprovedLabel) missingReasons.push('system-breaking-risk-scope');
if (requiresAgentDoubleCheck) {
  if (currentDoubleCheckStage === 2) {
    missingReasons.push('double-check-2-pending');
  } else {
    missingReasons.push('double-check-1-pending');
  }
}
if (noChecksReported && !noChecksNeutralForManagedPr) missingReasons.push('no-checks-reported');
if (pendingChecks.length > 0) missingReasons.push(...pendingChecks);
if (effectiveCheckFailures.length > 0) missingReasons.push(...effectiveCheckFailures);
if (!hasEffectiveCleanMergeState) missingReasons.push(`merge-state-${String(data.mergeStateStatus || '').toLowerCase() || 'unknown'}`);

const linkedIssueMatch = String(data.body || '').match(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b/i);
const branchIssueMatch = headRefName.match(managedIssueBranchRegex);
const linkedIssueId = linkedIssueMatch
  ? Number(linkedIssueMatch[1])
  : branchIssueMatch
    ? Number(branchIssueMatch.groups?.id || branchIssueMatch[1])
    : null;

let agentLane = 'ignore';
if (isManagedByAgent && !data.isDraft) {
  if (isBlocked) {
    agentLane = 'blocked';
  } else if (mergeStateStatus === 'DIRTY') {
    agentLane = 'merge-repair';
  } else if (hasManualFixOverride) {
    agentLane = 'fix';
  } else if (pendingChecks.length > 0) {
    agentLane = 'pending';
  } else if (scopeTooBroad) {
    agentLane = 'fix';
  } else if (hasOutstandingAgentStatusBlocker) {
    agentLane = 'fix';
  } else if ((hasManualFixOverride || hasActionableReviewComments) && !hasOutstandingNoopRepairSummary) {
    agentLane = 'fix';
  } else if (requiresExplicitHumanApproval && !hasHumanApprovedLabel && hasEffectiveCleanMergeState && !hasActionableReviewComments) {
    agentLane = 'human-review';
  } else if (requiresAgentDoubleCheck && hasEffectiveCleanMergeState && !hasActionableReviewComments) {
    agentLane = currentDoubleCheckStage === 2 ? 'double-check-2' : 'double-check-1';
  } else if (shouldCiRefresh) {
    agentLane = 'ci-refresh';
  } else if (missingReasons.length === 0) {
    agentLane = 'automerge';
  } else if (!hasEffectiveCleanMergeState || effectiveCheckFailures.length > 0) {
    agentLane = 'fix';
  } else if (effectiveChecksOk && requiresExplicitHumanApproval) {
    agentLane = 'human-review';
  } else if (effectiveChecksOk && requiresAgentDoubleCheck) {
    agentLane = currentDoubleCheckStage === 2 ? 'double-check-2' : 'double-check-1';
  }
}

if (
  laneOverride &&
  isManagedByAgent &&
  !data.isDraft &&
  !isBlocked &&
  !labelNames.includes('agent-running') &&
  !hasOutstandingAgentStatusBlocker &&
  !hasActionableReviewComments
) {
  if (laneOverride === 'double-check-2' && requiresAgentDoubleCheck && hasEffectiveCleanMergeState) {
    agentLane = 'double-check-2';
  } else if (laneOverride === 'double-check-1' && requiresAgentDoubleCheck && hasEffectiveCleanMergeState) {
    agentLane = 'double-check-1';
  }
}

const result = {
  number: data.number,
  title: data.title,
  url: data.url,
  headRefName,
  baseRefName: data.baseRefName,
  labels: labelNames,
  risk: riskTier,
  riskTier,
  riskReason,
  linkedIssueId,
  isAgentBranch: isManagedByAgent,
  isManagedByAgent,
  hasAgentHandoffLabel,
  hasAgentStatusComment,
  isBlocked,
  hasRepairQueuedLabel,
  hasManualFixNeededLabel,
  hasManualFixOverrideLabel,
  hasHumanApprovedLabel,
  hasDoubleCheckStageOneLabel,
  hasDoubleCheckStageTwoLabel,
  currentDoubleCheckStage,
  laneOverride,
  hasManualFixOverride,
  headCommittedAt,
  hasActionableReviewComments,
  actionableReviewCommentCount: actionableReviewComments.length,
  actionableReviewCommentUrls: actionableReviewComments.map((comment) => comment.html_url).filter(Boolean),
  isMobileRegressionPr,
  hasRequestedReviewers: reviewRequests.length > 0,
  localFirstVerificationPolicy,
  noChecksReported,
  checksOk,
  effectiveChecksOk,
  pendingChecks,
  checkFailures,
  effectiveCheckFailures,
  checksBypassed: hasInfraOnlyCheckFailures,
  infraOnlyCheckFailureMessages: failingCheckRunMessages,
  systemBreakingFiles,
  requiresExplicitHumanApproval,
  requiresAgentDoubleCheck,
  mergeStateStatus: data.mergeStateStatus,
  hasCleanMergeState,
  hasEffectiveCleanMergeState,
  hasNoopRepairSummary,
  hasOutstandingNoopRepairSummary,
  currentHeadStatusCommentCount: currentHeadStatusComments.length,
  latestAgentStatusIsCiOnlyBlocker,
  hasOutstandingAgentStatusBlocker,
  scopeTooBroad,
  scopeSplitReasons,
  productNonTestCount: productNonTestFiles.length,
  mobileProductCount: mobileProductFiles.length,
  mobileRouteFileCount: mobileRouteFiles.length,
  mobileSurfaceCount,
  localeResourceCount: localeResourceFiles.length,
  shouldCiRefresh,
  eligibleForAutoMerge: missingReasons.length === 0,
  missingReasons,
  agentLane,
  files,
};

process.stdout.write(JSON.stringify(result));
EOF
