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

mkdir -p "$repo_root/apps/api/src/modules/leave"

cat >"$repo_root/apps/api/src/modules/leave/leave.service.ts" <<'EOF'
export function cancelLeave(status) {
  return status === 'pending';
}
EOF

cat >"$repo_root/apps/api/src/modules/leave/leave.service.spec.ts" <<'EOF'
describe('leave service', () => {
  it('cancels pending requests', () => {
    expect(true).toBe(true)
  })
})
EOF

git -C "$repo_root" add .
git -C "$repo_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$repo_root" branch -M main >/dev/null 2>&1
git -C "$repo_root" push origin main >/dev/null 2>&1

git -C "$repo_root" checkout -b issue/narrow-api-slice >/dev/null 2>&1

cat >"$repo_root/apps/api/src/modules/leave/leave.service.ts" <<'EOF'
export function cancelLeave(status) {
  return status === 'pending' || status === 'approved';
}
EOF

cat >"$repo_root/apps/api/src/modules/leave/leave.service.spec.ts" <<'EOF'
describe('leave service', () => {
  it('allows approved requests in the targeted slice', () => {
    expect(true).toBe(true)
  })
})
EOF

cat >"$run_dir/verification.jsonl" <<'EOF'
{"status":"pass","command":"pnpm --filter api test -- --runInBand leave.service.spec.ts"}
{"status":"pass","command":"git diff --check"}
EOF

"$GUARD_SCRIPT" --worktree "$repo_root" --base-ref origin/main --run-dir "$run_dir" >/dev/null

echo "branch verification guard API narrow slice targeted test passed"
