#!/usr/bin/env bash
set -euo pipefail

INPUT_FILE=""
LABEL_PREFIX=""
OVERWRITE=0

usage() {
  echo "Usage: $0 --file <emails.txt> [--prefix <label_prefix>] [--allow-overwrite]"
  echo
  echo "Add multiple Codex accounts from a list of emails (one per line)."
  echo "For each email, runs: codex-quota codex add --no-browser <label>"
  echo "You must authenticate each account in the browser and enter the device code."
  echo
  echo "Options:"
  echo "  --file <path>        Required. File containing emails (one per line)."
  echo "  --prefix <string>    Optional prefix for generated labels (e.g., 'work-')."
  echo "  --allow-overwrite    Overwrite existing label if it already exists (skips by default)."
  echo "  -h, --help           Show this help."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --file)
      INPUT_FILE="$2"
      shift 2
      ;;
    --prefix)
      LABEL_PREFIX="$2"
      shift 2
      ;;
    --allow-overwrite)
      OVERWRITE=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
  echo "Error: --file is required." >&2
  usage
fi

if ! command -v codex-quota >/dev/null 2>&1; then
  echo "Error: codex-quota is not installed." >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input file not found: $INPUT_FILE" >&2
  exit 1
fi

# Get existing labels to avoid duplicates
EXISTING_LABELS=$(codex-quota codex list --json 2>/dev/null | jq -r '.accounts[].label' || true)

# Read emails line by line
LINE_NUM=0
while IFS= read -r email || [[ -n "$email" ]]; do
  LINE_NUM=$((LINE_NUM+1))
  # Skip empty lines and comments
  [[ -z "$email" ]] && continue
  [[ "$email" =~ ^# ]] && continue

  # Basic email validation
  if ! [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "Line $LINE_NUM: invalid email format, skipping: $email" >&2
    continue
  fi

  # Derive label from email prefix
  PREFIX="${LABEL_PREFIX}"
  if [[ -z "$PREFIX" ]]; then
    PREFIX=$(echo "$email" | awk -F'@' '{print $1}' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
  else
    PREFIX=$(echo "$PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
  fi
  # Ensure non-empty
  if [[ -z "$PREFIX" ]]; then
    PREFIX="acct${LINE_NUM}"
  fi

  # Check if label exists
  if echo "$EXISTING_LABELS" | grep -qx "$PREFIX"; then
    if (( OVERWRITE == 0 )); then
      echo "Label '$PREFIX' already exists. Skipping. Use --allow-overwrite to replace."
      continue
    else
      echo "Label '$PREFIX' exists but --allow-overwrite set. You may re-add it (will update tokens)."
    fi
  fi

  echo "========================================"
  echo "Adding account: $email -> label: $PREFIX"
  echo "----------------------------------------"
  echo "A browser window should open. If not, follow the printed URL."
  echo "You will need to log in and enter the device code."
  echo "Press ENTER to continue after successful authentication; Ctrl+C to abort this account."
  echo "----------------------------------------"
  read -r -t 5 -p "Starting OAuth in 5 seconds... (Ctrl+C to cancel) " _

  # Run codex-quota add with --no-browser to print URL and wait for callback
  if codex-quota codex add "$PREFIX" --no-browser; then
    echo "Added account: $PREFIX"
  else
    echo "Failed to add account: $PREFIX" >&2
  fi

  # Refresh existing labels for next iteration
  EXISTING_LABELS=$(codex-quota codex list --json 2>/dev/null | jq -r '.accounts[].label' || true)

  echo ""
done < "$INPUT_FILE"

echo "Batch add complete."
