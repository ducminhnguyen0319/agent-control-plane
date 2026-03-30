#!/usr/bin/env bash
set -euo pipefail

ISSUE_BODY="${ISSUE_BODY:-${1:-}}"

ISSUE_BODY="$ISSUE_BODY" node <<'EOF'
const body = process.env.ISSUE_BODY || '';
const scheduled = /^\s*(?:Agent schedule|Schedule|Cadence)\s*:\s*(?:every\s+)?(\d+)\s*([mhd])\s*$/im.test(body);

if (!scheduled) {
  process.stdout.write('no\n');
  process.exit(0);
}

if (/^\s*(?:Local workspace install|Worktree local install)\s*:\s*yes\s*$/im.test(body)) {
  process.stdout.write('yes\n');
  process.exit(0);
}

const installLikePatterns = [
  /(^|\n)\s*\d+\.\s*`(?:pnpm|npm|yarn)\s+(?:install|i|ci|add|remove|rm|up|update|rebuild|dlx)\b/im,
  /(^|\n)\s*\d+\.\s*`pnpm\s+exec\s+pod\s+install\b/im,
  /(^|\n)\s*\d+\.\s*`(?:npx\s+pod-install|expo\s+prebuild|pod\s+install|bundle\s+install)\b/im,
  /`(?:pnpm|npm|yarn)\s+(?:install|i|ci|add|remove|rm|up|update|rebuild|dlx)\b/im,
  /`pnpm\s+exec\s+pod\s+install\b/im,
  /`(?:npx\s+pod-install|expo\s+prebuild|pod\s+install|bundle\s+install)\b/im,
];

const needsLocalInstall = installLikePatterns.some((pattern) => pattern.test(body));
process.stdout.write(needsLocalInstall ? 'yes\n' : 'no\n');
EOF
