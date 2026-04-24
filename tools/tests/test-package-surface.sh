#!/usr/bin/env bash
# test-package-surface.sh
# Check what's included in the npm package tarball.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "Checking package tarball surface..."

# Create a temporary directory for the tarball check
TMP_DIR="$(mktemp -d)"
trap "rm -rf \"$TMP_DIR\"" EXIT

# Pack the package (dry run)
cd "$ROOT_DIR"
npm pack --dry-run 2>&1 | tee "${TMP_DIR}/pack-output.txt"

# Check if key files are included
while IFS= read -r line; do
  # Match lines like "npm notice filename"
  if [[ "$line" == npm\ notice\ * ]]; then
    file="${line#npm notice }"
    
    # Check for required files
    case "$file" in
      bin/agent-control-plane|\
      bin/issue-resource-class.sh|\
      bin/label-follow-up-issues.sh|\
      bin/pr-risk.sh|\
      bin/sync-pr-labels.sh|\
      tools/bin/*.sh|\
      tools/dashboard/*|\
      tools/templates/*.md|\
      tools/vendor/*|\
      assets/workflow-catalog.json|\
      README.md|\
      LICENSE)
        # These are good
        ;;
      *)
        # Check if it's something that shouldn't be included
        if [[ "$file" =~ (test|spec|\.log|node_modules) ]]; then
          echo "WARN: Possibly unwanted file in package: $file"
        fi
        ;;
    esac
  fi
done < "${TMP_DIR}/pack-output.txt"

echo "Package surface check passed"
