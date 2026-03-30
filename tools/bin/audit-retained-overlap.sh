#!/usr/bin/env bash
set -euo pipefail

PRIMARY_ROOT=""
SECONDARY_ROOT=""
PRIMARY_LABEL="primary"
SECONDARY_LABEL="secondary"
SUMMARY_ONLY="false"

usage() {
  cat <<'EOF'
Usage:
  audit-retained-overlap.sh --primary <path> --secondary <path> [options]

Compares uncommitted file sets between two retained human worktrees.

Options:
  --primary <path>            Primary retained worktree
  --secondary <path>          Secondary retained worktree
  --primary-label <label>     Label for primary output (default: primary)
  --secondary-label <label>   Label for secondary output (default: secondary)
  --summary-only              Print counts and grouped summaries only
  --help                      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --primary) PRIMARY_ROOT="${2:-}"; shift 2 ;;
    --secondary) SECONDARY_ROOT="${2:-}"; shift 2 ;;
    --primary-label) PRIMARY_LABEL="${2:-}"; shift 2 ;;
    --secondary-label) SECONDARY_LABEL="${2:-}"; shift 2 ;;
    --summary-only) SUMMARY_ONLY="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$PRIMARY_ROOT" || -z "$SECONDARY_ROOT" ]]; then
  usage >&2
  exit 1
fi

for repo_root in "$PRIMARY_ROOT" "$SECONDARY_ROOT"; do
  if [[ ! -d "$repo_root/.git" && ! -f "$repo_root/.git" ]]; then
    echo "not a git checkout: $repo_root" >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/retained-overlap.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

collect_changed_files() {
  local repo_root="${1:?repo root required}"
  git -C "$repo_root" status --porcelain | sed -E 's/^...//' | sort -u
}

group_paths() {
  awk -F/ '
    NF == 0 { next }
    {
      limit = (NF < 5 ? NF : 5)
      key = $1
      for (i = 2; i <= limit; i++) {
        key = key "/" $i
      }
      print key
    }
  ' | sort | uniq -c | sort -nr | sed 's/^ *//'
}

collect_changed_files "$PRIMARY_ROOT" >"${tmp_dir}/primary.txt"
collect_changed_files "$SECONDARY_ROOT" >"${tmp_dir}/secondary.txt"

comm -12 "${tmp_dir}/primary.txt" "${tmp_dir}/secondary.txt" >"${tmp_dir}/overlap.txt"
comm -23 "${tmp_dir}/primary.txt" "${tmp_dir}/secondary.txt" >"${tmp_dir}/primary-only.txt"
comm -13 "${tmp_dir}/primary.txt" "${tmp_dir}/secondary.txt" >"${tmp_dir}/secondary-only.txt"

primary_count="$(wc -l <"${tmp_dir}/primary.txt" | tr -d ' ')"
secondary_count="$(wc -l <"${tmp_dir}/secondary.txt" | tr -d ' ')"
overlap_count="$(wc -l <"${tmp_dir}/overlap.txt" | tr -d ' ')"
primary_only_count="$(wc -l <"${tmp_dir}/primary-only.txt" | tr -d ' ')"
secondary_only_count="$(wc -l <"${tmp_dir}/secondary-only.txt" | tr -d ' ')"

printf '%s_ROOT=%s\n' "$(printf '%s' "$PRIMARY_LABEL" | tr '[:lower:]-' '[:upper:]_')" "$PRIMARY_ROOT"
printf '%s_ROOT=%s\n' "$(printf '%s' "$SECONDARY_LABEL" | tr '[:lower:]-' '[:upper:]_')" "$SECONDARY_ROOT"
printf '%s_COUNT=%s\n' "$(printf '%s' "$PRIMARY_LABEL" | tr '[:lower:]-' '[:upper:]_')" "$primary_count"
printf '%s_COUNT=%s\n' "$(printf '%s' "$SECONDARY_LABEL" | tr '[:lower:]-' '[:upper:]_')" "$secondary_count"
printf 'OVERLAP_COUNT=%s\n' "$overlap_count"
printf '%s_ONLY_COUNT=%s\n' "$(printf '%s' "$PRIMARY_LABEL" | tr '[:lower:]-' '[:upper:]_')" "$primary_only_count"
printf '%s_ONLY_COUNT=%s\n' "$(printf '%s' "$SECONDARY_LABEL" | tr '[:lower:]-' '[:upper:]_')" "$secondary_only_count"
printf '\n'

printf '[%s-only-groups]\n' "$PRIMARY_LABEL"
if [[ -s "${tmp_dir}/primary-only.txt" ]]; then
  group_paths <"${tmp_dir}/primary-only.txt"
else
  printf 'none\n'
fi
printf '\n'

printf '[%s-only-groups]\n' "$SECONDARY_LABEL"
if [[ -s "${tmp_dir}/secondary-only.txt" ]]; then
  group_paths <"${tmp_dir}/secondary-only.txt"
else
  printf 'none\n'
fi
printf '\n'

printf '[overlap-groups]\n'
if [[ -s "${tmp_dir}/overlap.txt" ]]; then
  group_paths <"${tmp_dir}/overlap.txt"
else
  printf 'none\n'
fi
printf '\n'

if [[ "$SUMMARY_ONLY" == "true" ]]; then
  exit 0
fi

printf '[%s-only-files]\n' "$PRIMARY_LABEL"
cat "${tmp_dir}/primary-only.txt"
printf '\n'

printf '[%s-only-files]\n' "$SECONDARY_LABEL"
cat "${tmp_dir}/secondary-only.txt"
printf '\n'

printf '[overlap-files]\n'
cat "${tmp_dir}/overlap.txt"
