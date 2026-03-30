#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  sync-recurring-issue-checklist.sh --repo-slug <owner/repo> --issue-id <id> [--dry-run]

Best-effort sync of recurring keep-open issue checklist boxes against merged PR
history referenced from prior "Opened PR #..." issue comments.
EOF
}

repo_slug=""
issue_id=""
dry_run="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-slug) repo_slug="${2:-}"; shift 2 ;;
    --issue-id) issue_id="${2:-}"; shift 2 ;;
    --dry-run) dry_run="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${repo_slug}" || -z "${issue_id}" ]]; then
  usage >&2
  exit 1
fi

issue_json="$(flow_github_issue_view_json "${repo_slug}" "${issue_id}")"
pr_numbers="$(
  ISSUE_JSON="${issue_json}" node -e '
const issue = JSON.parse(process.env.ISSUE_JSON || "{}");
const seen = new Set();
const numbers = [];
for (const comment of issue.comments || []) {
  const body = String((comment && comment.body) || "");
  for (const match of body.matchAll(/Opened PR #(\d+)/g)) {
    const prNumber = String(match[1] || "").trim();
    if (!prNumber || seen.has(prNumber)) continue;
    seen.add(prNumber);
    numbers.push(prNumber);
  }
}
process.stdout.write(numbers.join("\n"));
'
)"

pr_jsonl_file="$(mktemp)"
sync_json_file="$(mktemp)"
trap 'rm -f "${pr_jsonl_file}" "${sync_json_file}"' EXIT

while IFS= read -r pr_number; do
  [[ -n "${pr_number}" ]] || continue
  pr_json="$(flow_github_pr_view_json "${repo_slug}" "${pr_number}" 2>/dev/null || true)"
  [[ -n "${pr_json}" ]] || continue
  printf '%s\n' "${pr_json}" >>"${pr_jsonl_file}"
done <<<"${pr_numbers}"

ISSUE_JSON="${issue_json}" PR_JSONL_FILE="${pr_jsonl_file}" node <<'EOF' >"${sync_json_file}"
const fs = require('fs');

const issue = JSON.parse(process.env.ISSUE_JSON || '{}');
const issueBody = String(issue.body || '');
const prJsonlFile = process.env.PR_JSONL_FILE || '';
const prs = [];

if (prJsonlFile && fs.existsSync(prJsonlFile)) {
  const raw = fs.readFileSync(prJsonlFile, 'utf8');
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    prs.push(JSON.parse(trimmed));
  }
}

const labels = new Set((issue.labels || []).map((label) => String(label?.name || '')));
const isRecurring = labels.has('agent-keep-open');
const lines = issueBody.split(/\r?\n/);
const checklistPattern = /^(\s*-\s+\[)( |x|X)(\]\s+)(.*)$/;
const allChecklistCompletedComment = (issue.comments || []).find((comment) =>
  /^# Blocker: All checklist items already completed\b/m.test(String(comment?.body || '')),
);

const stopWords = new Set([
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'do', 'does', 'each',
  'for', 'from', 'if', 'in', 'into', 'is', 'it', 'its', 'now', 'of', 'on',
  'one', 'only', 'or', 'per', 'so', 'than', 'that', 'the', 'their', 'them',
  'then', 'this', 'to', 'up', 'with', 'within',
]);

const splitCamel = (value) =>
  String(value || '')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/([A-Z])([A-Z][a-z])/g, '$1 $2');

const normalizeWords = (value) =>
  splitCamel(value)
    .replace(/[`*_()[\]{}:;,!?/\\]+/g, ' ')
    .replace(/\.(?=[A-Za-z])/g, ' ')
    .toLowerCase()
    .split(/[^a-z0-9-]+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 3 && !stopWords.has(token));

const unique = (items) => [...new Set(items.filter(Boolean))];

const extractCodeTokens = (value) => {
  const raw = String(value || '');
  const tokens = [];
  for (const match of raw.matchAll(/`([^`]+)`/g)) {
    tokens.push(match[1]);
  }
  for (const match of raw.matchAll(/\B--[a-z0-9-]+\b/gi)) {
    tokens.push(match[0]);
  }
  for (const match of raw.matchAll(/\b[a-z][a-z0-9]*(?:[A-Z][a-z0-9]+)+\b/g)) {
    tokens.push(match[0]);
  }
  return unique(
    tokens.map((token) =>
      String(token || '')
        .replace(/[`*_()[\]{}:;,!?/\\]+/g, ' ')
        .trim()
        .toLowerCase(),
    ),
  );
};

const mergedPrs = prs.filter((pr) => String(pr.mergedAt || '').trim() || String(pr.state || '').toUpperCase() === 'MERGED');

const buildPrMatcher = (pr) => {
  const combined = `${pr.title || ''}\n${pr.body || ''}`;
  return {
    number: pr.number,
    combinedLower: combined.toLowerCase(),
    words: new Set(normalizeWords(combined)),
    codeTokens: new Set(extractCodeTokens(combined)),
  };
};

const prMatchers = mergedPrs.map(buildPrMatcher);

const matchChecklistItem = (itemText) => {
  const itemWords = unique(normalizeWords(itemText));
  const itemCodeTokens = unique(extractCodeTokens(itemText));
  let best = null;

  for (const pr of prMatchers) {
    const matchedWords = itemWords.filter((word) => pr.words.has(word));
    const matchedCodeTokens = itemCodeTokens.filter((token) =>
      pr.codeTokens.has(token) || pr.combinedLower.includes(token),
    );
    const wordScore = itemWords.length > 0 ? matchedWords.length / itemWords.length : 0;
    const codeScore = itemCodeTokens.length > 0 ? matchedCodeTokens.length / itemCodeTokens.length : 0;

    let matched = false;
    if (itemCodeTokens.length > 0) {
      matched =
        (matchedCodeTokens.length > 0 && (codeScore >= 0.5 || wordScore >= 0.35)) ||
        (matchedWords.length >= 2 && wordScore >= 0.45);
    } else {
      matched = matchedWords.length >= 2 && wordScore >= 0.45;
    }

    if (!matched) continue;

    const candidate = {
      number: pr.number,
      wordScore,
      codeScore,
      matchedWords: matchedWords.length,
      matchedCodeTokens: matchedCodeTokens.length,
    };

    if (
      !best ||
      candidate.codeScore > best.codeScore ||
      candidate.wordScore > best.wordScore ||
      candidate.matchedWords > best.matchedWords
    ) {
      best = candidate;
    }
  }

  return best;
};

const checklistEntries = [];
const matchedPrNumbers = new Set();
let changed = false;

const updatedLines = lines.map((line, index) => {
  const match = line.match(checklistPattern);
  if (!match) return line;

  const checked = String(match[2] || '').toLowerCase() === 'x';
  const text = String(match[4] || '');
  const entry = { index, checked, text, matchedPr: null };

  if (!checked) {
    if (allChecklistCompletedComment) {
      changed = true;
      checklistEntries.push({ ...entry, checked: true, matchedByWorkflowComment: true });
      return `${match[1]}x${match[3]}${text}`;
    }

    entry.matchedPr = matchChecklistItem(text);
    if (entry.matchedPr) {
      matchedPrNumbers.add(String(entry.matchedPr.number));
      changed = true;
      checklistEntries.push({ ...entry, checked: true });
      return `${match[1]}x${match[3]}${text}`;
    }
  }

  checklistEntries.push(entry);
  return line;
});

const total = checklistEntries.length;
const checkedCount = checklistEntries.filter((entry) => entry.checked || entry.matchedPr).length;
const uncheckedCount = Math.max(total - checkedCount, 0);

let status = 'noop';
if (!isRecurring) {
  status = 'skipped-not-recurring';
} else if (total === 0) {
  status = 'skipped-no-checklist';
} else if (changed) {
  status = 'updated';
}

const result = {
  status,
  total,
  checked: checkedCount,
  unchecked: uncheckedCount,
  changed,
  matchedPrNumbers: [...matchedPrNumbers],
  body: changed ? updatedLines.join('\n') : issueBody,
};

process.stdout.write(`${JSON.stringify(result)}\n`);
EOF

sync_status="$(jq -r '.status' "${sync_json_file}")"
total_count="$(jq -r '.total' "${sync_json_file}")"
checked_count="$(jq -r '.checked' "${sync_json_file}")"
unchecked_count="$(jq -r '.unchecked' "${sync_json_file}")"
changed="$(jq -r '.changed' "${sync_json_file}")"
matched_pr_numbers="$(jq -r '.matchedPrNumbers | join(",")' "${sync_json_file}")"

if [[ "${dry_run}" != "true" && "${changed}" == "true" ]]; then
  updated_body="$(jq -r '.body' "${sync_json_file}")"
  flow_github_issue_update_body "${repo_slug}" "${issue_id}" "${updated_body}"
fi

printf 'CHECKLIST_SYNC_STATUS=%s\n' "${sync_status}"
printf 'CHECKLIST_TOTAL=%s\n' "${total_count}"
printf 'CHECKLIST_CHECKED=%s\n' "${checked_count}"
printf 'CHECKLIST_UNCHECKED=%s\n' "${unchecked_count}"
printf 'CHECKLIST_MATCHED_PR_NUMBERS=%s\n' "${matched_pr_numbers}"
