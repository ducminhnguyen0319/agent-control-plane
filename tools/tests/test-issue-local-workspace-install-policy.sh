#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_BIN="${FLOW_ROOT}/tools/bin/issue-requires-local-workspace-install.sh"

scheduled_verify_body="$(cat <<'EOF'
## Summary
Run a recurring read-only verification.

Schedule: every 1h

## Commands
1. `pnpm run verify:web:main`
EOF
)"

scheduled_mobile_verify_body="$(cat <<'EOF'
## Summary
Run a recurring read-only verification.

Schedule: every 1h

## Commands
1. `pnpm run verify:mobile:main`
EOF
)"

scheduled_install_body="$(cat <<'EOF'
## Summary
Rebuild the workspace before running checks.

Schedule: every 1h

## Commands
1. `pnpm install --frozen-lockfile`
2. `pnpm run verify:web:main`
EOF
)"

scheduled_native_body="$(cat <<'EOF'
## Summary
Prepare iOS workspace before recurring checks.

Schedule: every 1h

## Commands
1. `expo prebuild --platform ios`
2. `pnpm run verify:mobile:main`
EOF
)"

explicit_opt_in_body="$(cat <<'EOF'
## Summary
Run with local install.

Schedule: every 1h
Local workspace install: yes

## Commands
1. `pnpm run verify:web:main`
EOF
)"

unscheduled_install_body="$(cat <<'EOF'
## Summary
Manual task.

## Commands
1. `pnpm install --frozen-lockfile`
EOF
)"

[[ "$(ISSUE_BODY="$scheduled_verify_body" bash "$POLICY_BIN")" == "no" ]]
[[ "$(ISSUE_BODY="$scheduled_mobile_verify_body" bash "$POLICY_BIN")" == "no" ]]
[[ "$(ISSUE_BODY="$scheduled_install_body" bash "$POLICY_BIN")" == "yes" ]]
[[ "$(ISSUE_BODY="$scheduled_native_body" bash "$POLICY_BIN")" == "yes" ]]
[[ "$(ISSUE_BODY="$explicit_opt_in_body" bash "$POLICY_BIN")" == "yes" ]]
[[ "$(ISSUE_BODY="$unscheduled_install_body" bash "$POLICY_BIN")" == "no" ]]

echo "issue local workspace install policy test passed"
