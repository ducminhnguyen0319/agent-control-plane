#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  issue-publish-scope-guard.sh --worktree <path> --base-ref <git-ref> [--issue-id <number>]

Fail fast when an issue worker branch is too broad to publish safely as a single
PR slice.
EOF
}

worktree=""
base_ref=""
issue_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) worktree="${2:-}"; shift 2 ;;
    --base-ref) base_ref="${2:-}"; shift 2 ;;
    --issue-id) issue_id="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$worktree" || -z "$base_ref" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$worktree" ]]; then
  echo "missing worktree: $worktree" >&2
  exit 1
fi

changed_files="$(
  git -C "$worktree" diff --name-only --diff-filter=ACMR "${base_ref}...HEAD"
)"

issue_title=""
issue_body=""
if [[ -n "$issue_id" ]]; then
  CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
  REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
  issue_json="$(flow_github_issue_view_json "${REPO_SLUG}" "${issue_id}" 2>/dev/null || true)"
  if [[ -n "$issue_json" ]]; then
    issue_title="$(jq -r '.title // ""' <<<"$issue_json" 2>/dev/null || true)"
    issue_body="$(jq -r '.body // ""' <<<"$issue_json" 2>/dev/null || true)"
  fi
fi

CHANGED_FILES="$changed_files" ISSUE_ID="$issue_id" ISSUE_TITLE="$issue_title" ISSUE_BODY="$issue_body" node <<'EOF'
const files = String(process.env.CHANGED_FILES || '')
  .split('\n')
  .map((file) => file.trim())
  .filter(Boolean);

const issueId = String(process.env.ISSUE_ID || '').trim();
const issueTitle = String(process.env.ISSUE_TITLE || '').trim();
const issueBody = String(process.env.ISSUE_BODY || '').trim();

const isDoc = (file) =>
  /^openspec\//.test(file) ||
  /^docs\//.test(file) ||
  /^scripts\/README\.md$/.test(file) ||
  /\.md$/i.test(file);

const isTest = (file) =>
  /(?:^|\/)__tests__\//.test(file) ||
  /(?:^|\/)e2e\//.test(file) ||
  /\.(?:spec|test)\.[cm]?[jt]sx?$/.test(file);

const isLocaleResource = (file) =>
  /^packages\/i18n\/src\/resources\/[^/]+\.json$/.test(file);

const isProductNonTest = (file) =>
  !isDoc(file) &&
  !isTest(file) &&
  !isLocaleResource(file) &&
  (/^apps\//.test(file) || /^packages\//.test(file));

const isMobileRouteFile = (file) =>
  /^apps\/mobile\/app\/.+\.[cm]?[jt]sx?$/.test(file) &&
  !isTest(file);

const mobileSurfaceKey = (file) => {
  const relative = file
    .replace(/^apps\/mobile\/app\//, '')
    .replace(/\.[cm]?[jt]sx?$/, '');
  const segments = relative
    .split('/')
    .filter(Boolean)
    .filter((segment) => !/^\(.+\)$/.test(segment));
  if (segments.length === 0) return relative;
  return segments[0];
};

const isAuthCriticalProductFile = (file) =>
  /^apps\/api\/src\/modules\/auth\//.test(file) ||
  file === 'apps/api/src/entities/user.entity.ts' ||
  /^apps\/api\/src\/migrations\/.*(?:Email|Phone|Auth|User).*\.[cm]?[jt]s$/.test(file) ||
  /^apps\/api\/src\/common\/utils\/(?:phone|tenant|email|auth)[^/]*\.[cm]?[jt]s$/.test(file);

const isAuthAdjacentProductFile = (file) =>
  isAuthCriticalProductFile(file) ||
  /^apps\/web\/src\/app\/\(auth\)\//.test(file) ||
  /^apps\/api\/src\/modules\/organization\//.test(file);

const productNonTestFiles = files.filter(isProductNonTest);
const mobileProductFiles = productNonTestFiles.filter((file) => /^apps\/mobile\//.test(file));
const localeResourceFiles = files.filter(isLocaleResource);
const mobileRouteFiles = productNonTestFiles.filter(isMobileRouteFile);
const mobileSurfaceKeys = [...new Set(mobileRouteFiles.map(mobileSurfaceKey))];
const authCriticalTouched = productNonTestFiles.some(isAuthCriticalProductFile);
const authMixedScopeFiles = authCriticalTouched
  ? productNonTestFiles.filter((file) => !isAuthAdjacentProductFile(file))
  : [];
const openspecChangeFiles = files.filter((file) => /^openspec\/changes\//.test(file));
const workflowRuleFiles = files.filter((file) =>
  /^(?:AGENTS\.md|openspec\/AGENT_RULES\.md)$/.test(file),
);
const docsDeclaredScope =
  /^(?:docs?|documentation)\b/i.test(issueTitle) ||
  /^docs?\(/i.test(issueTitle) ||
  /\b(?:docs?|documentation|openspec)[ -]?only\b/i.test(issueTitle) ||
  /(?:^|\n)\s*(?:scope|mode|type)\s*:\s*(?:docs?|documentation|openspec)(?:[- ]only)?\b/i.test(issueBody) ||
  /(?:^|\n)\s*(?:docs?|documentation|openspec)[ -]?only\b/i.test(issueBody);

const reasons = [];
if (productNonTestFiles.length > 14) {
  reasons.push(`product_non_test_count=${productNonTestFiles.length} exceeds max=14`);
}
if (mobileProductFiles.length >= 8) {
  reasons.push(`mobile_product_count=${mobileProductFiles.length} exceeds max=7`);
}
if (localeResourceFiles.length > 8 && productNonTestFiles.length >= 6) {
  reasons.push(
    `locale_resource_count=${localeResourceFiles.length} with product_non_test_count=${productNonTestFiles.length} exceeds mixed-scope limit`,
  );
}
if (mobileRouteFiles.length > 3) {
  reasons.push(`mobile_route_file_count=${mobileRouteFiles.length} exceeds max=3`);
}
if (mobileSurfaceKeys.length > 2) {
  reasons.push(`mobile_surface_count=${mobileSurfaceKeys.length} exceeds max=2`);
}
if (authMixedScopeFiles.length > 0) {
  reasons.push(
    `auth_mixed_scope_count=${authMixedScopeFiles.length} requires a dedicated auth slice before publish`,
  );
}
if (docsDeclaredScope && productNonTestFiles.length > 0) {
  reasons.push(`docs_declared_scope_contains_product_changes=${productNonTestFiles.length}`);
}
if (openspecChangeFiles.length > 0 && productNonTestFiles.length > 0) {
  reasons.push(
    `product_and_openspec_change_mix=product:${productNonTestFiles.length},openspec_change:${openspecChangeFiles.length}`,
  );
}
if (workflowRuleFiles.length > 0 && productNonTestFiles.length > 0) {
  reasons.push(
    `workflow_rule_files_mixed_with_product_changes=${workflowRuleFiles.length}`,
  );
}

if (reasons.length === 0) {
  process.stdout.write('SCOPE_GUARD_STATUS=ok\n');
  process.stdout.write(`PRODUCT_NON_TEST_COUNT=${productNonTestFiles.length}\n`);
  process.stdout.write(`MOBILE_PRODUCT_COUNT=${mobileProductFiles.length}\n`);
  process.stdout.write(`LOCALE_RESOURCE_COUNT=${localeResourceFiles.length}\n`);
  process.stdout.write(`MOBILE_ROUTE_FILE_COUNT=${mobileRouteFiles.length}\n`);
  process.stdout.write(`MOBILE_SURFACE_COUNT=${mobileSurfaceKeys.length}\n`);
  process.stdout.write(`AUTH_MIXED_SCOPE_COUNT=${authMixedScopeFiles.length}\n`);
  process.exit(0);
}

const lines = [
  `Scope guard blocked issue${issueId ? ` #${issueId}` : ''} from publishing as a single PR.`,
  '',
  'The branch is too broad for the current flow and should be split into a smaller slice before publish.',
  '',
  'Why it was blocked:',
  ...reasons.map((reason) => `- ${reason}`),
];

if (productNonTestFiles.length > 0) {
  lines.push('', 'Representative product files:');
  for (const file of productNonTestFiles.slice(0, 12)) {
    lines.push(`- ${file}`);
  }
}

if (localeResourceFiles.length > 0) {
  lines.push('', 'Locale resource files touched:');
  for (const file of localeResourceFiles.slice(0, 12)) {
    lines.push(`- ${file}`);
  }
}

if (openspecChangeFiles.length > 0) {
  lines.push('', 'OpenSpec change files touched:');
  for (const file of openspecChangeFiles.slice(0, 12)) {
    lines.push(`- ${file}`);
  }
}

if (workflowRuleFiles.length > 0) {
  lines.push('', 'Workflow or repo-rule files touched:');
  for (const file of workflowRuleFiles.slice(0, 12)) {
    lines.push(`- ${file}`);
  }
}

if (mobileRouteFiles.length > 0) {
  lines.push('', 'Mobile route files touched:');
  for (const file of mobileRouteFiles.slice(0, 12)) {
    lines.push(`- ${file}`);
  }
}

if (authMixedScopeFiles.length > 0) {
  lines.push('', 'Files that should move to a separate follow-up PR from the auth slice:');
  for (const file of authMixedScopeFiles.slice(0, 12)) {
    lines.push(`- ${file}`);
  }
}

lines.push(
  '',
  'Required next step:',
  '- re-run the issue as a narrower slice that stays within one primary product surface, at most two mobile route surfaces, one dedicated auth/security contract change, or one docs/OpenSpec-only branch with no product code',
);

process.stderr.write(`${lines.join('\n')}\n`);
process.exit(42);
EOF
