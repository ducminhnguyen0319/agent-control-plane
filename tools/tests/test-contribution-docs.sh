#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

test -f "$ROOT_DIR/CONTRIBUTING.md"
test -f "$ROOT_DIR/CLA.md"
test -f "$ROOT_DIR/.github/pull_request_template.md"

grep -q 'This CLA is a license grant, not a copyright assignment\.' "$ROOT_DIR/CLA.md"
grep -q 'You retain copyright in your contribution\.' "$ROOT_DIR/CLA.md"
grep -q 'relicense the contribution' "$ROOT_DIR/CLA.md"
grep -q 'The PR template includes a checkbox for this\.' "$ROOT_DIR/CONTRIBUTING.md"
grep -q 'sponsorships do not automatically create payment obligations to contributors' "$ROOT_DIR/CONTRIBUTING.md"
grep -q 'sponsorship does not transfer ownership, copyright, patent rights, or control' "$ROOT_DIR/README.md"
grep -q '\[CLA.md\](\./CLA.md)' "$ROOT_DIR/README.md"

echo "contribution docs test passed"
