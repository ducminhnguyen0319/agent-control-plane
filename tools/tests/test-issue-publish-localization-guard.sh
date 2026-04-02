#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD_BIN="${FLOW_ROOT}/tools/bin/issue-publish-localization-guard.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
git init -b main "$repo" >/dev/null 2>&1

mkdir -p "$repo/apps/web/src/components/admin" "$repo/packages/i18n/src/resources"
cat >"$repo/apps/web/src/components/admin/OnboardingWizard.tsx" <<'EOF'
export function OnboardingWizard() {
  return null;
}
EOF
cat >"$repo/packages/i18n/src/resources/en.json" <<'EOF'
{}
EOF
git -C "$repo" add .
git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null

git -C "$repo" checkout -b issue-slice >/dev/null 2>&1
cat >"$repo/apps/web/src/components/admin/OnboardingWizard.tsx" <<'EOF'
const schema = {
  firstName: z.string().min(1, 'First name is required'),
};

export function OnboardingWizard() {
  return <input placeholder="John" aria-label="First name" />;
}
EOF
cat >"$repo/packages/i18n/src/resources/en.json" <<'EOF'
{"admin":{"onboarding":{"title":"Customer onboarding wizard"}}}
EOF
git -C "$repo" add .
git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "localized wizard draft" >/dev/null

set +e
blocked_output="$(
  bash "$GUARD_BIN" --worktree "$repo" --base-ref main 2>&1
)"
blocked_status=$?
set -e

test "$blocked_status" = "44"
grep -q 'Localization guard blocked branch publication.' <<<"$blocked_output"
grep -q 'validation_literal:' <<<"$blocked_output"
grep -q 'string_prop:' <<<"$blocked_output"

git -C "$repo" checkout main >/dev/null 2>&1
git -C "$repo" checkout -b clean-slice >/dev/null 2>&1
cat >"$repo/apps/web/src/components/admin/OnboardingWizard.tsx" <<'EOF'
export function OnboardingWizard() {
  const { t } = useSafeTranslation();
  return <input placeholder={t('admin.onboarding.firstNamePlaceholder', 'First name')} />;
}
EOF
cat >"$repo/packages/i18n/src/resources/en.json" <<'EOF'
{"admin":{"onboarding":{"firstNamePlaceholder":"First name"}}}
EOF
git -C "$repo" add .
git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -m "localized wizard clean" >/dev/null

bash "$GUARD_BIN" --worktree "$repo" --base-ref main >/dev/null

echo "issue publish localization guard test passed"
