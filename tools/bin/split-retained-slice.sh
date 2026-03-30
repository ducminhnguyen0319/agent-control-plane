#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=""
TARGET_ROOT=""
PATHS_FILE=""
BACKUP_ROOT=""
MOVE_MODE="false"

usage() {
  cat <<'EOF'
Usage:
  split-retained-slice.sh --source <path> --target <path> --paths-file <file> [options]

Copies a curated slice of uncommitted changes from one retained worktree to
another. Optionally removes that slice from the source after verifying the copy.

Options:
  --source <path>       Source retained worktree
  --target <path>       Target retained worktree
  --paths-file <file>   Newline-delimited relative paths to copy
  --backup-root <path>  Where to store a safety backup copy (default: mktemp)
  --move                Remove the copied paths from the source after verify
  --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_ROOT="${2:-}"; shift 2 ;;
    --target) TARGET_ROOT="${2:-}"; shift 2 ;;
    --paths-file) PATHS_FILE="${2:-}"; shift 2 ;;
    --backup-root) BACKUP_ROOT="${2:-}"; shift 2 ;;
    --move) MOVE_MODE="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$SOURCE_ROOT" || -z "$TARGET_ROOT" || -z "$PATHS_FILE" ]]; then
  usage >&2
  exit 1
fi

for required_path in "$SOURCE_ROOT" "$TARGET_ROOT" "$PATHS_FILE"; do
  [[ -e "$required_path" ]] || { echo "missing path: $required_path" >&2; exit 1; }
done

if [[ ! -d "$SOURCE_ROOT/.git" && ! -f "$SOURCE_ROOT/.git" ]]; then
  echo "source is not a git checkout: $SOURCE_ROOT" >&2
  exit 1
fi
if [[ ! -d "$TARGET_ROOT/.git" && ! -f "$TARGET_ROOT/.git" ]]; then
  echo "target is not a git checkout: $TARGET_ROOT" >&2
  exit 1
fi

if [[ -n "$(git -C "$TARGET_ROOT" status --short)" ]]; then
  echo "target worktree must be clean before splitting: $TARGET_ROOT" >&2
  exit 1
fi

if [[ -z "$BACKUP_ROOT" ]]; then
  BACKUP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/retained-slice-backup.XXXXXX")"
else
  mkdir -p "$BACKUP_ROOT"
fi

copy_path() {
  local source_path="${1:?source path required}"
  local dest_root="${2:?destination root required}"
  local rel_path="${3:?relative path required}"

  if [[ -d "$source_path" ]]; then
    mkdir -p "$(dirname "${dest_root}/${rel_path}")"
    rm -rf "${dest_root}/${rel_path}"
    cp -R "$source_path" "${dest_root}/${rel_path}"
  else
    mkdir -p "$(dirname "${dest_root}/${rel_path}")"
    cp -p "$source_path" "${dest_root}/${rel_path}"
  fi
}

tracked_path_exists() {
  local repo_root="${1:?repo root required}"
  local rel_path="${2:?relative path required}"
  git -C "$repo_root" ls-files --error-unmatch -- "$rel_path" >/dev/null 2>&1
}

while IFS= read -r rel_path || [[ -n "$rel_path" ]]; do
  [[ -n "$rel_path" ]] || continue
  [[ "$rel_path" != \#* ]] || continue

  source_path="${SOURCE_ROOT}/${rel_path}"
    [[ -e "$source_path" ]] || { echo "source path missing: $rel_path" >&2; exit 1; }

    copy_path "$source_path" "$BACKUP_ROOT" "$rel_path"
    copy_path "$source_path" "$TARGET_ROOT" "$rel_path"

  diff -qr "$source_path" "${TARGET_ROOT}/${rel_path}" >/dev/null
done <"$PATHS_FILE"

if [[ "$MOVE_MODE" == "true" ]]; then
  while IFS= read -r rel_path || [[ -n "$rel_path" ]]; do
    [[ -n "$rel_path" ]] || continue
    [[ "$rel_path" != \#* ]] || continue

    was_tracked="false"
    if tracked_path_exists "$SOURCE_ROOT" "$rel_path"; then
      was_tracked="true"
      git -C "$SOURCE_ROOT" restore --worktree --source=HEAD -- "$rel_path"
    fi

    if [[ "$was_tracked" != "true" && -e "${SOURCE_ROOT}/${rel_path}" ]]; then
      rm -rf "${SOURCE_ROOT:?}/${rel_path}"
    fi
  done <"$PATHS_FILE"
fi

printf 'SOURCE_ROOT=%s\n' "$SOURCE_ROOT"
printf 'TARGET_ROOT=%s\n' "$TARGET_ROOT"
printf 'PATHS_FILE=%s\n' "$PATHS_FILE"
printf 'BACKUP_ROOT=%s\n' "$BACKUP_ROOT"
printf 'MOVE_MODE=%s\n' "$MOVE_MODE"
