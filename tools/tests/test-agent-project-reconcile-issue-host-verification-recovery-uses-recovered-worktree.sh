#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-reconcile-issue-session"
RECORD_VERIFICATION_SCRIPT="${FLOW_ROOT}/tools/bin/record-verification.sh"
RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
shared_bin="$shared_home/tools/bin"
runs_root="$tmpdir/runs"
repo_root="$tmpdir/repo"
origin_root="$tmpdir/origin.git"
recovery_worktree="$tmpdir/recovery-worktree"
session="demo-issue-13"
run_dir="$runs_root/$session"
capture_file="$tmpdir/publish-attempts.log"

mkdir -p "$shared_bin" "$runs_root" "$repo_root" "$run_dir"
cp "$SOURCE_SCRIPT" "$shared_bin/agent-project-reconcile-issue-session"
cp "$RECORD_VERIFICATION_SCRIPT" "$shared_bin/record-verification.sh"
cp "$RESIDENT_LIB" "$shared_bin/flow-resident-worker-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"

cat >"$shared_bin/agent-project-worker-status" <<EOF_STATUS
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=%s\n' "$session"
printf 'STATUS=SUCCEEDED\n'
printf 'META_FILE=%s\n' "$run_dir/run.env"
EOF_STATUS

cat >"$shared_bin/agent-project-publish-issue-pr" <<'EOF_PUBLISH'
#!/usr/bin/env bash
set -euo pipefail

runs_root=""
session=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs-root) runs_root="${2:-}"; shift 2 ;;
    --session) session="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

run_dir="${runs_root}/${session}"
verification_file="${run_dir}/verification.jsonl"
attempt_count="$(wc -l <"${TEST_CAPTURE_FILE:?}" 2>/dev/null || echo 0)"
printf 'ATTEMPT\n' >>"${TEST_CAPTURE_FILE:?}"

if [[ "$attempt_count" == "0" ]]; then
  printf 'WORKTREE_RECOVERY=created\n' >&2
  printf 'RECOVERY_WORKTREE=%s\n' "${TEST_RECOVERY_WORKTREE:?}" >&2
  printf 'Verification guard blocked branch publication.\n' >&2
  exit 1
fi

if [[ ! -f "$verification_file" ]]; then
  printf 'Verification guard blocked branch publication.\n' >&2
  exit 1
fi
if ! grep -Fq '"command":"npm test"' "$verification_file"; then
  printf 'Verification guard blocked branch publication.\n' >&2
  exit 1
fi
if ! grep -Fq '"command":"node --test test/task-metrics.test.js"' "$verification_file"; then
  printf 'Verification guard blocked branch publication.\n' >&2
  exit 1
fi

printf 'PUBLISH_STATUS=created-pr\n'
printf 'PR_NUMBER=45\n'
printf 'PR_URL=https://github.com/example/repo/pull/45\n'
EOF_PUBLISH

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF_CLEANUP'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_CLEANUP

cat >"$shared_bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}:${2:-}" in
  api:user)
    printf 'tester\n'
    ;;
  *)
    exit 0
    ;;
esac
EOF_GH

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/record-verification.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-publish-issue-pr" \
  "$shared_bin/agent-project-cleanup-session" \
  "$shared_bin/gh"

git init --bare "$origin_root" >/dev/null 2>&1
git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Test"
git -C "$repo_root" config user.email "test@example.com"

cat >"$repo_root/package.json" <<'EOF_PACKAGE'
{
  "name": "demo-repo",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF_PACKAGE

mkdir -p "$repo_root/src" "$repo_root/test"
cat >"$repo_root/src/task-metrics.js" <<'EOF_SRC'
export function metricValue() {
  return 1;
}
EOF_SRC
cat >"$repo_root/test/task-metrics.test.js" <<'EOF_TEST'
import test from 'node:test';
import assert from 'node:assert/strict';
import { metricValue } from '../src/task-metrics.js';

test('metricValue returns branch value', () => {
  assert.equal(metricValue(), 2);
});
EOF_TEST
git -C "$repo_root" add package.json src/task-metrics.js test/task-metrics.test.js
git -C "$repo_root" commit -m "init" >/dev/null 2>&1
git -C "$repo_root" remote add origin "$origin_root"
git -C "$repo_root" push -u origin main >/dev/null 2>&1

git -C "$repo_root" checkout -b agent/demo/issue-13 >/dev/null 2>&1
cat >"$repo_root/src/task-metrics.js" <<'EOF_SRC_BRANCH'
export function metricValue() {
  return 2;
}
EOF_SRC_BRANCH
cat >"$repo_root/test/task-metrics.test.js" <<'EOF_TEST_BRANCH'
import test from 'node:test';
import assert from 'node:assert/strict';
import { metricValue } from '../src/task-metrics.js';

test('metricValue returns updated branch value', () => {
  assert.equal(metricValue(), 2);
});
EOF_TEST_BRANCH
git -C "$repo_root" add src/task-metrics.js test/task-metrics.test.js
git -C "$repo_root" commit -m "feat: update metric value" >/dev/null 2>&1

git clone "$repo_root" "$recovery_worktree" >/dev/null 2>&1
git -C "$recovery_worktree" checkout agent/demo/issue-13 >/dev/null 2>&1

cat >"$run_dir/run.env" <<EOF_RUN
ISSUE_ID=13
BRANCH=agent/demo/issue-13
WORKTREE=$tmpdir/missing-worktree
EOF_RUN

cat >"$run_dir/result.env" <<'EOF_RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
ISSUE_ID=13
EOF_RESULT

cat >"$run_dir/prompt.md" <<'EOF_PROMPT'
# Task

Rules for each cycle:
- Run `npm test` after code changes.

Target files:
- `src/task-metrics.js`
- `test/task-metrics.test.js`
EOF_PROMPT

output="$(
  TEST_CAPTURE_FILE="$capture_file" \
  TEST_RECOVERY_WORKTREE="$recovery_worktree" \
  PATH="$shared_bin:$PATH" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session "$session" \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$tmpdir/history"
)"

grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^PR_NUMBER=45$' <<<"$output"
grep -q '^RESULT_CONTRACT_NOTE=host-recovered-verification-guard-blocked$' <<<"$output"
grep -q '"command":"npm test"' "$run_dir/verification.jsonl"
grep -q '"command":"node --test test/task-metrics.test.js"' "$run_dir/verification.jsonl"
attempt_count="$(wc -l <"$capture_file" | tr -d ' ')"
[[ "$attempt_count" == "2" ]]

echo "agent-project reconcile issue host verification recovery uses recovered worktree test passed"
