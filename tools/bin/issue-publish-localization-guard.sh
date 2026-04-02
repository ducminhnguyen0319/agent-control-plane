#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  issue-publish-localization-guard.sh --worktree <path> --base-ref <git-ref>

Fail fast when an issue branch updates locale resources but still leaves obvious
hardcoded user-facing strings in the touched UI files.
EOF
}

worktree=""
base_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) worktree="${2:-}"; shift 2 ;;
    --base-ref) base_ref="${2:-}"; shift 2 ;;
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

CHANGED_FILES="${changed_files}" WORKTREE="${worktree}" node <<'EOF'
const fs = require('fs');
const path = require('path');

const changedFiles = String(process.env.CHANGED_FILES || '')
  .split('\n')
  .map((file) => file.trim())
  .filter(Boolean);
const worktree = String(process.env.WORKTREE || '');

const localeFiles = changedFiles.filter((file) =>
  /^packages\/i18n\/src\/resources\/[^/]+\.json$/.test(file),
);
if (localeFiles.length === 0) {
  process.stdout.write('LOCALIZATION_GUARD_STATUS=skipped-no-locale-files\n');
  process.exit(0);
}

const uiFiles = changedFiles.filter((file) =>
  /^(?:apps\/web\/|apps\/mobile\/|packages\/ui\/).+\.[cm]?[jt]sx?$/.test(file),
);
if (uiFiles.length === 0) {
  process.stdout.write('LOCALIZATION_GUARD_STATUS=skipped-no-ui-files\n');
  process.exit(0);
}

const suspiciousPatterns = [
  {
    reason: 'validation_literal',
    test: (line) =>
      /\.(?:min|max|length|email|regex|nonempty)\([^)]*,\s*['"`][^'"`]*[A-Za-z][^'"`]*['"`]/.test(line),
  },
  {
    reason: 'string_prop',
    test: (line) =>
      /\b(?:title|description|actionLabel|aria-label|placeholder)\s*=\s*['"][^'{"][^'"]*[A-Za-z][^'"]*['"]/.test(
        line,
      ),
  },
  {
    reason: 'object_label_literal',
    test: (line) =>
      /\blabel\s*:\s*['"][A-Za-z][^'"]*['"]/.test(line),
  },
];

const ignoreLine = (line) => {
  const trimmed = line.trim();
  if (!trimmed) return true;
  if (/^\s*\/\//.test(trimmed)) return true;
  if (/\bt\(/.test(trimmed)) return true;
  if (/\buseSafeTranslation\b|\buseTranslation\b|\bi18nKey=/.test(trimmed)) return true;
  if (/^import\s/.test(trimmed)) return true;
  return false;
};

const findings = [];
for (const relativeFile of uiFiles) {
  const absoluteFile = path.join(worktree, relativeFile);
  if (!fs.existsSync(absoluteFile)) continue;
  const lines = fs.readFileSync(absoluteFile, 'utf8').split(/\r?\n/);
  lines.forEach((line, index) => {
    if (ignoreLine(line)) return;
    for (const pattern of suspiciousPatterns) {
      if (pattern.test(line)) {
        findings.push({
          file: relativeFile,
          line: index + 1,
          reason: pattern.reason,
          text: line.trim(),
        });
        return;
      }
    }
  });
}

if (findings.length === 0) {
  process.stdout.write('LOCALIZATION_GUARD_STATUS=ok\n');
  process.stdout.write(`LOCALE_RESOURCE_COUNT=${localeFiles.length}\n`);
  process.stdout.write(`UI_FILE_COUNT=${uiFiles.length}\n`);
  process.exit(0);
}

const lines = [
  'Localization guard blocked branch publication.',
  '',
  'The branch updates locale resources but still leaves obvious hardcoded user-facing strings in touched UI files.',
  '',
  'Why it was blocked:',
];
for (const finding of findings.slice(0, 20)) {
  lines.push(`- ${finding.reason}: ${finding.file}:${finding.line} -> ${finding.text}`);
}
lines.push(
  '',
  'Required next step:',
  '- move the remaining user-facing literals behind translation keys before publishing this issue branch',
);

process.stderr.write(`${lines.join('\n')}\n`);
process.exit(44);
EOF
