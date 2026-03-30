#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD_SCRIPT="${FLOW_ROOT}/tools/bin/branch-verification-guard.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

origin_repo="$tmpdir/origin.git"
repo_root="$tmpdir/repo-root"
run_dir="$tmpdir/run"

mkdir -p "$run_dir"

git init --bare "$origin_repo" >/dev/null 2>&1
git clone "$origin_repo" "$repo_root" >/dev/null 2>&1

mkdir -p \
  "$repo_root/apps/api/src/modules/auth" \
  "$repo_root/apps/web/e2e/archive/auth" \
  "$repo_root/apps/web/src/app/(auth)/login"

cat >"$repo_root/apps/api/src/modules/auth/auth.service.ts" <<'EOF'
export const loginFailureMode = 'legacy';
EOF

cat >"$repo_root/apps/api/src/modules/auth/auth.service.extended.spec.ts" <<'EOF'
describe('auth service', () => {
  it('handles login failures', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$repo_root/apps/web/src/app/(auth)/login/page.tsx" <<'EOF'
export default function LoginPage() {
  return null
}
EOF

cat >"$repo_root/apps/web/src/app/(auth)/login/page.spec.tsx" <<'EOF'
describe('login page', () => {
  it('renders', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$repo_root/apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts" <<'EOF'
test('tenant isolation login', async () => {
  expect(true).toBeTruthy()
})
EOF

git -C "$repo_root" add .
git -C "$repo_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$repo_root" branch -M main >/dev/null 2>&1
git -C "$repo_root" push origin main >/dev/null 2>&1

git -C "$repo_root" checkout -b openclaw/pr-coverage >/dev/null 2>&1

cat >"$repo_root/apps/api/src/modules/auth/auth.service.ts" <<'EOF'
export const loginFailureMode = 'generic-invalid-credentials';
EOF

cat >"$repo_root/apps/api/src/modules/auth/auth.service.extended.spec.ts" <<'EOF'
describe('auth service', () => {
  it('normalizes tenant login failures', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$repo_root/apps/web/src/app/(auth)/login/page.tsx" <<'EOF'
export default function LoginPage() {
  return 'Invalid credentials'
}
EOF

cat >"$repo_root/apps/web/src/app/(auth)/login/page.spec.tsx" <<'EOF'
describe('login page', () => {
  it('shows the generic invalid credentials message', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$repo_root/apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts" <<'EOF'
test('tenant isolation login hides tenant existence', async () => {
  expect(true).toBeTruthy()
})
EOF

cat >"$run_dir/verification.jsonl" <<'EOF'
{"status":"pass","command":"pnpm --filter api typecheck"}
{"status":"pass","command":"pnpm --filter api test -- --testPathPatterns=\"auth.service.extended\""}
{"status":"pass","command":"pnpm --filter web test -- login/page.spec"}
EOF

set +e
guard_output="$("$GUARD_SCRIPT" --worktree "$repo_root" --base-ref origin/main --run-dir "$run_dir" 2>&1)"
guard_status=$?
set -e

test "$guard_status" = "43"
grep -q 'changed test files were not covered by a targeted test command' <<<"$guard_output"
grep -q 'Changed test files still missing explicit coverage:' <<<"$guard_output"
grep -q 'apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts' <<<"$guard_output"
if grep -q 'apps/api/src/modules/auth/auth.service.extended.spec.ts | accepted anchors' <<<"$guard_output"; then
  echo "API spec should have been recognized as covered by auth.service.extended test command" >&2
  exit 1
fi
if grep -q 'apps/web/src/app/(auth)/login/page.spec.tsx | accepted anchors' <<<"$guard_output"; then
  echo "web page spec should have been recognized as covered by login/page.spec test command" >&2
  exit 1
fi

cat >>"$run_dir/verification.jsonl" <<'EOF'
{"status":"pass","command":"pnpm exec playwright test apps/web/e2e/archive/auth/tenant-isolation-login.spec.ts"}
EOF

"$GUARD_SCRIPT" --worktree "$repo_root" --base-ref origin/main --run-dir "$run_dir" >/dev/null

echo "branch verification guard targeted coverage test passed"
