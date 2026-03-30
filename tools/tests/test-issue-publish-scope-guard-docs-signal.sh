#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCOPE_GUARD_BIN="${FLOW_ROOT}/tools/bin/issue-publish-scope-guard.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
bin_dir="$tmpdir/bin"
node_bin_dir="$(dirname "$(command -v node)")"
mkdir -p "$bin_dir"

git init -b main "$repo" >/dev/null 2>&1
mkdir -p "$repo/apps/web/src/app"
printf 'export default function Home() { return null; }\n' >"$repo/apps/web/src/app/page.tsx"
git -C "$repo" add apps/web/src/app/page.tsx
git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null
git -C "$repo" checkout -b issue-slice >/dev/null 2>&1
printf 'export default function Home() { return \"patched\"; }\n' >"$repo/apps/web/src/app/page.tsx"
git -C "$repo" add apps/web/src/app/page.tsx
git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "product slice" >/dev/null

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-}"
  case "$issue_id" in
    100)
      cat <<'JSON'
{"title":"Align auth page with OpenSpec contract","body":"Context: keep behavior aligned with the latest OpenSpec notes."}
JSON
      ;;
    101)
      cat <<'JSON'
{"title":"docs: auth page follow-up","body":"Scope: docs only"}
JSON
      ;;
    *)
      echo "unexpected issue id: $issue_id" >&2
      exit 1
      ;;
  esac
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$SCOPE_GUARD_BIN" --worktree "$repo" --base-ref main --issue-id 100 >/dev/null

set +e
blocked_output="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$SCOPE_GUARD_BIN" --worktree "$repo" --base-ref main --issue-id 101 2>&1
)"
blocked_status=$?
set -e

test "$blocked_status" = "42"
grep -q 'docs_declared_scope_contains_product_changes=1' <<<"$blocked_output"

echo "issue publish scope guard docs signal test passed"
