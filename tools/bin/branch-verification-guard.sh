#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  branch-verification-guard.sh --worktree <path> --base-ref <git-ref> --run-dir <path>

Fail fast when a branch update is about to be pushed without sufficient local
verification evidence for the touched surface.
EOF
}

worktree=""
base_ref=""
run_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) worktree="${2:-}"; shift 2 ;;
    --base-ref) base_ref="${2:-}"; shift 2 ;;
    --run-dir) run_dir="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$worktree" || -z "$base_ref" || -z "$run_dir" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$worktree" ]]; then
  echo "missing worktree: $worktree" >&2
  exit 1
fi

changed_files="$(
  {
    git -C "$worktree" diff --name-only --diff-filter=ACMR "${base_ref}...HEAD"
    git -C "$worktree" diff --name-only --diff-filter=ACMR
    git -C "$worktree" diff --cached --name-only --diff-filter=ACMR
    git -C "$worktree" ls-files --others --exclude-standard 2>/dev/null || true
  } | awk '
      NF == 0 { next }
      !seen[$0]++ { print $0 }
    '
)"

verification_file="${run_dir}/verification.jsonl"

CHANGED_FILES="$changed_files" VERIFICATION_FILE="$verification_file" node <<'EOF'
const fs = require('fs');
const path = require('path');

const files = String(process.env.CHANGED_FILES || '')
  .split('\n')
  .map((file) => file.trim())
  .filter(Boolean);
const normalizePath = (file) => String(file || '').replace(/\\/g, '/').toLowerCase();
const stripCodeExtension = (file) => normalizePath(file).replace(/\.[cm]?[jt]sx?$/i, '');
const stripTestSuffix = (file) => stripCodeExtension(file).replace(/\.(spec|test)$/i, '');
const lastPathSegments = (file, count = 2) => {
  const parts = normalizePath(file).split('/').filter(Boolean);
  return parts.slice(-count).join('/');
};
const unique = (values) => [...new Set(values.filter(Boolean))];

const verificationFile = String(process.env.VERIFICATION_FILE || '');
const isDoc = (file) =>
  /^openspec\//.test(file) ||
  /^docs\//.test(file) ||
  /^scripts\/README\.md$/.test(file) ||
  /^AGENTS\.md$/.test(file) ||
  /^openspec\/AGENT_RULES\.md$/.test(file) ||
  /\.md$/i.test(file);

const isTest = (file) =>
  /(?:^|\/)__tests__\//.test(file) ||
  /(?:^|\/)e2e\//.test(file) ||
  /\.(?:spec|test)\.[cm]?[jt]sx?$/.test(file);

const isLocaleResource = (file) =>
  /^packages\/i18n\/src\/resources\/[^/]+\.json$/.test(file);
const isAgentGeneratedArtifact = (file) =>
  /^\.agent-session\.env$/i.test(file) ||
  /^(?:\.openclaw-artifacts|\.openclaw)(?:\/|$)/i.test(file) ||
  /^(?:SOUL|TOOLS|IDENTITY|USER|HEARTBEAT|BOOTSTRAP)\.md$/i.test(file);
const isDependencyLockfile = (file) =>
  /(?:^|\/)(?:pnpm-lock\.yaml|package-lock\.json|yarn\.lock|bun\.lockb|npm-shrinkwrap\.json)$/i.test(file);
const isDependencyManifest = (file) =>
  /(?:^|\/)package\.json$/i.test(file) ||
  /(?:^|\/)pnpm-workspace\.yaml$/i.test(file) ||
  /(?:^|\/)\.npmrc$/i.test(file) ||
  /(?:^|\/)\.yarnrc(?:\.yml)?$/i.test(file) ||
  /(?:^|\/)bunfig\.toml$/i.test(file);

const productNonTestFiles = files.filter(
  (file) => !isDoc(file) && !isTest(file) && !isLocaleResource(file),
);
const generatedArtifacts = unique(files.filter(isAgentGeneratedArtifact));
const dependencyLockfiles = unique(files.filter(isDependencyLockfile));
const dependencyInputsChanged = files.some(isDependencyManifest);
const apiTouched = productNonTestFiles.some((file) => /^apps\/api\//.test(file));
const webTouched = productNonTestFiles.some((file) => /^apps\/web\//.test(file));
const mobileTouched = productNonTestFiles.some((file) => /^apps\/mobile\//.test(file));
const packageNames = [
  ...new Set(
    productNonTestFiles
      .filter((file) => /^packages\//.test(file))
      .map((file) => file.split('/')[1])
      .filter(Boolean),
  ),
];
const changedTestFiles = files.filter(isTest);
const localeTouched = files.some(isLocaleResource);

if (productNonTestFiles.length === 0 && !localeTouched && changedTestFiles.length === 0) {
  process.stdout.write('VERIFICATION_GUARD_STATUS=ok\n');
  process.stdout.write('VERIFICATION_REASON=docs-or-spec-only\n');
  process.exit(0);
}

let entries = [];
if (verificationFile && fs.existsSync(verificationFile)) {
  const raw = fs.readFileSync(verificationFile, 'utf8');
  entries = raw
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch (error) {
        return [];
      }
    });
}

const passedCommands = entries
  .filter((entry) => entry && entry.status === 'pass' && typeof entry.command === 'string')
  .map((entry) => entry.command.trim())
  .filter(Boolean);
const passedLower = passedCommands.map((command) => command.toLowerCase());

const escapeRegex = (value) => String(value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const hasCommand = (...patterns) =>
  passedLower.some((command) => patterns.some((pattern) => pattern.test(command)));
const hasScopedCommand = (scopePatterns, ...actionPatterns) =>
  passedLower.some(
    (command) =>
      scopePatterns.some((pattern) => pattern.test(command)) &&
      actionPatterns.some((pattern) => pattern.test(command)),
  );
const workspaceScopePatterns = (workspace) => {
  const name = escapeRegex(workspace);
  return [
    new RegExp(`--filter(?:=|\\s+)(?:@[^/\\s]+/)?${name}\\b`),
    new RegExp(`(?:\\bapps/${name}\\b|(?:--dir|-C)\\s+apps/${name}\\b)`),
  ];
};
const packageScopePatterns = (pkg) => {
  const name = escapeRegex(pkg);
  return [
    new RegExp(`--filter(?:=|\\s+)(?:@[^/\\s]+/)?${name}\\b`),
    new RegExp(`@[^/\\s]+/${name}\\b`),
    new RegExp(`(?:\\bpackages/${name}\\b|(?:--dir|-C)\\s+packages/${name}\\b)`),
  ];
};
const apiScopePattern = workspaceScopePatterns('api');
const webScopePattern = workspaceScopePatterns('web');
const mobileScopePattern = workspaceScopePatterns('mobile');
const targetedAnchorsForFile = (file) =>
  unique([
    stripCodeExtension(lastPathSegments(file, 2)),
    stripCodeExtension(path.basename(file)),
    path.basename(stripTestSuffix(file)),
  ]);
const hasScopedRunnerCoverage = (file, command) => {
  if (/(?:^|\/)e2e\//.test(file)) {
    return /\bplaywright\b/.test(command);
  }
  if (/^apps\/mobile\//.test(file)) {
    return /\b(?:detox|maestro)\b/.test(command);
  }
  return false;
};
const changedTestCoverage = changedTestFiles.map((file) => {
  const anchors = targetedAnchorsForFile(file);
  const covered = passedLower.some(
    (command) =>
      anchors.some((anchor) => anchor && command.includes(anchor)) ||
      hasScopedRunnerCoverage(file, command),
  );
  return { file, anchors, covered };
});
const missingChangedTestFiles = changedTestCoverage.filter(({ covered }) => !covered);

const rootTypecheck = hasCommand(/\bpnpm (?:run )?typecheck\b/, /\bturbo\b.*\btypecheck\b/);
const rootBuild = hasCommand(/\bpnpm (?:run )?build\b/, /\bturbo\b.*\bbuild\b/);
const rootLint = hasCommand(/\bpnpm (?:run )?lint\b/, /\bturbo\b.*\blint\b/);
const rootTest = hasCommand(/\bpnpm (?:run )?test\b/, /\bturbo\b.*\btest\b/);

const reasons = [];
if (passedCommands.length === 0) {
  reasons.push('missing verification journal or no successful verification commands were recorded');
}

if (generatedArtifacts.length > 0) {
  reasons.push('generated agent/session artifacts were included in the branch diff');
}

if (dependencyLockfiles.length > 0 && !dependencyInputsChanged) {
  reasons.push('lockfile changes were introduced without dependency manifest changes');
}

if (localeTouched) {
  if (
    !hasCommand(
      /(?:@[^/\s]+\/i18n\b|--filter(?:=|\s+)(?:@[^/\s]+\/i18n|i18n)\b).*?\bvalidate\b/,
      /\bi18n-validation\b/,
      /\bi18n-gate\b/,
      /\b(?:i18n|locale|translation|translations)\b.*\bvalidate\b/,
    )
  ) {
    reasons.push('missing i18n validate command for locale resource changes');
  }
  if (
    !hasCommand(
      /(?:@[^/\s]+\/i18n\b|--filter(?:=|\s+)(?:@[^/\s]+\/i18n|i18n)\b).*?\b(?:scan-hardcoded|i18n:scan)\b/,
      /\bi18n-checks\b/,
      /\bi18n-gate\b/,
      /\b(?:i18n|locale|translation|translations)\b.*\b(?:scan-hardcoded|i18n:scan|scan)\b/,
    )
  ) {
    reasons.push('missing i18n scan-hardcoded command for locale resource changes');
  }
}

if (apiTouched) {
  if (!(hasScopedCommand(apiScopePattern, /\btypecheck\b/, /\btsc --noemit\b/, /\btsc --noemit\b/) || rootTypecheck)) {
    reasons.push('missing API typecheck or repo typecheck for API changes');
  }
  if (!(hasScopedCommand(apiScopePattern, /\blint\b/, /\bbuild\b/, /\btest\b/, /\bjest\b/, /\bvitest\b/) || rootBuild || rootLint || rootTest)) {
    reasons.push('missing API confidence verification (lint, build, or test) for API changes');
  }
}

if (webTouched) {
  if (!(hasScopedCommand(webScopePattern, /\blint\b/, /\btypecheck\b/, /\bbuild\b/, /\btest\b/, /\bjest\b/, /\bvitest\b/) || rootTypecheck || rootBuild || rootLint || rootTest)) {
    reasons.push('missing Web verification command for web changes');
  }
}

if (mobileTouched) {
  if (!(hasScopedCommand(mobileScopePattern, /\blint\b/, /\btypecheck\b/, /\bbuild\b/, /\btest\b/, /\bjest\b/, /\bvitest\b/, /\bdetox\b/, /\bmaestro\b/) || rootTypecheck || rootBuild || rootLint || rootTest || hasCommand(/\bdetox\b/, /\bmaestro\b/))) {
    reasons.push('missing Mobile verification command for mobile changes');
  }
}

if (!apiTouched && !webTouched && !mobileTouched && packageNames.length > 0) {
  for (const pkg of packageNames) {
    if (
      !(hasScopedCommand(
        packageScopePatterns(pkg),
        /\blint\b/,
        /\btypecheck\b/,
        /\bbuild\b/,
        /\btest\b/,
        /\bjest\b/,
        /\bvitest\b/,
      ) || rootTypecheck || rootBuild || rootLint || rootTest)
    ) {
      reasons.push(`missing shared package verification for packages/${pkg}`);
    }
  }
}

if (missingChangedTestFiles.length > 0) {
  reasons.push('changed test files were not covered by a targeted test command');
}

if (reasons.length === 0) {
  process.stdout.write('VERIFICATION_GUARD_STATUS=ok\n');
  process.stdout.write(`VERIFICATION_COMMAND_COUNT=${passedCommands.length}\n`);
  process.exit(0);
}

const lines = [
  'Verification guard blocked branch publication.',
  '',
  'Why it was blocked:',
  ...reasons.map((reason) => `- ${reason}`),
];

if (productNonTestFiles.length > 0) {
  lines.push('', 'Changed product files:');
  for (const file of productNonTestFiles.slice(0, 15)) {
    lines.push(`- ${file}`);
  }
}

if (generatedArtifacts.length > 0) {
  lines.push('', 'Generated artifacts that must be removed before publish:');
  for (const file of generatedArtifacts.slice(0, 15)) {
    lines.push(`- ${file}`);
  }
}

if (dependencyLockfiles.length > 0 && !dependencyInputsChanged) {
  lines.push('', 'Lockfiles changed without a matching dependency manifest update:');
  for (const file of dependencyLockfiles.slice(0, 15)) {
    lines.push(`- ${file}`);
  }
}

if (missingChangedTestFiles.length > 0) {
  lines.push('', 'Changed test files still missing explicit coverage:');
  for (const { file, anchors } of missingChangedTestFiles.slice(0, 15)) {
    const acceptedAnchors = anchors.map((anchor) => `\`${anchor}\``);
    if (/(?:^|\/)e2e\//.test(file)) {
      acceptedAnchors.push('scoped `playwright` command');
    } else if (/^apps\/mobile\//.test(file)) {
      acceptedAnchors.push('scoped `detox` or `maestro` command');
    }
    lines.push(`- ${file} | accepted anchors: ${acceptedAnchors.join(', ')}`);
  }
}

if (passedCommands.length > 0) {
  lines.push('', 'Recorded verification commands:');
  for (const command of passedCommands.slice(0, 20)) {
    lines.push(`- ${command}`);
  }
} else {
  lines.push('', `Verification journal file: ${verificationFile || '(missing)'}`);
}

lines.push(
  '',
  'Required next step:',
  '- rerun the narrowest relevant local verification, record each successful command into verification.jsonl, then publish again',
);

process.stderr.write(`${lines.join('\n')}\n`);
process.exit(43);
EOF
