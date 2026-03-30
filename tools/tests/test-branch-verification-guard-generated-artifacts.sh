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
mkdir -p "$repo_root/src"

cat >"$repo_root/package.json" <<'EOF'
{
  "name": "guard-demo",
  "private": true,
  "scripts": {
    "test": "node --test"
  }
}
EOF

cat >"$repo_root/src/index.js" <<'EOF'
export const status = 'ready';
EOF

git -C "$repo_root" add .
git -C "$repo_root" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$repo_root" branch -M main >/dev/null 2>&1
git -C "$repo_root" push origin main >/dev/null 2>&1

git -C "$repo_root" checkout -b guard/generated-artifacts >/dev/null 2>&1

cat >"$repo_root/src/index.js" <<'EOF'
export const status = 'updated';
EOF

cat >"$repo_root/.agent-session.env" <<'EOF'
export ACP_SESSION='demo-issue-1'
EOF

cat >"$repo_root/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'
EOF

cat >"$run_dir/verification.jsonl" <<'EOF'
{"status":"pass","command":"npm test"}
EOF

set +e
guard_output="$("$GUARD_SCRIPT" --worktree "$repo_root" --base-ref origin/main --run-dir "$run_dir" 2>&1)"
guard_status=$?
set -e

test "$guard_status" = "43"
grep -q 'generated agent/session artifacts were included in the branch diff' <<<"$guard_output"
grep -q 'lockfile changes were introduced without dependency manifest changes' <<<"$guard_output"
grep -q '.agent-session.env' <<<"$guard_output"
grep -q 'pnpm-lock.yaml' <<<"$guard_output"

rm -f "$repo_root/.agent-session.env" "$repo_root/pnpm-lock.yaml"

"$GUARD_SCRIPT" --worktree "$repo_root" --base-ref origin/main --run-dir "$run_dir" >/dev/null

echo "branch verification guard generated artifacts test passed"
