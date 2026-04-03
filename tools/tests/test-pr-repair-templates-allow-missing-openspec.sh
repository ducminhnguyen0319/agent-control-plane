#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

grep -Fq 'If present, read `{REPO_ROOT}/openspec/AGENT_RULES.md`.' \
  "${ROOT_DIR}/tools/templates/pr-fix-template.md"
grep -Fq 'If present, read `{REPO_ROOT}/docs/TESTING_AND_SEED_POLICY.md`.' \
  "${ROOT_DIR}/tools/templates/pr-fix-template.md"
grep -Fq '`openspec list` if the repo uses OpenSpec' \
  "${ROOT_DIR}/tools/templates/pr-fix-template.md"

grep -Fq 'If present, read `{REPO_ROOT}/openspec/AGENT_RULES.md`.' \
  "${ROOT_DIR}/tools/templates/pr-merge-repair-template.md"
grep -Fq 'If present, read `{REPO_ROOT}/docs/TESTING_AND_SEED_POLICY.md`.' \
  "${ROOT_DIR}/tools/templates/pr-merge-repair-template.md"
grep -Fq '`openspec list` if the repo uses OpenSpec' \
  "${ROOT_DIR}/tools/templates/pr-merge-repair-template.md"

