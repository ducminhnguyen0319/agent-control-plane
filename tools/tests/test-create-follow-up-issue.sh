#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/create-follow-up-issue.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
labels_log="$tmpdir/labels.log"
body_capture="$tmpdir/body.txt"
mkdir -p "$bin_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  body_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body-file)
        body_file="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  cat "$body_file" >"${TEST_BODY_CAPTURE:?}"
  printf 'https://github.com/example/repo/issues/912\n'
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh"

cat >"$bin_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_LABELS_LOG:?}"
EOF
chmod +x "$bin_dir/agent-github-update-labels"

body_file="$tmpdir/follow-up.md"
cat >"$body_file" <<'EOF'
Target slice: mobile settings language cluster

- Keep PR to one route family
- Reuse account cluster shell
EOF

TEST_BODY_CAPTURE="$body_capture" \
TEST_LABELS_LOG="$labels_log" \
UPDATE_LABELS_BIN="$bin_dir/agent-github-update-labels" \
PATH="$bin_dir:$PATH" \
bash "$SCRIPT" \
  --parent 421 \
  --title "Mobile settings: split language cluster from umbrella" \
  --body-file "$body_file" \
  --label agent-e2e-heavy >"$tmpdir/out.txt"

grep -q '^ISSUE_NUMBER=912$' "$tmpdir/out.txt"
grep -q '^ISSUE_URL=https://github.com/example/repo/issues/912$' "$tmpdir/out.txt"
grep -q '^Parent issue: #421$' "$body_capture"
grep -q 'Target slice: mobile settings language cluster' "$body_capture"
grep -q -- '--number 912 --add agent-e2e-heavy' "$labels_log"

echo "create follow-up issue test passed"
