#!/usr/bin/env bash
# test-docs-links.sh
# Simple check for broken internal links in markdown files.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXIT_CODE=0

echo "Checking for broken internal links in markdown files..."

# Find all markdown files
while IFS= read -r -d '' file; do
  # Get directory of the file for resolving relative links
  file_dir="$(dirname "$file")"
  
  # Skip node_modules, .git, etc.
  if [[ "$file" =~ (node_modules|\.git|dist|build)/ ]]; then
    continue
  fi
  
  # Extract markdown links [text](url) - one per line
  # Using grep to find all [text](url) patterns
  grep -o '\[[^]]*\]([^)]*)' "$file" 2>/dev/null | while IFS= read -r match; do
    # Skip if empty
    [[ -z "$match" ]] && continue
    
    # Extract URL from [text](url)
    url="$(echo "$match" | sed 's/.*(//;s/)$//')"
    
    # Skip external links
    if [[ "$url" =~ ^https?:// ]]; then
      continue
    fi
    
    # Skip anchor links (just #section)
    if [[ "$url" =~ ^# ]]; then
      continue
    fi
    
    # Remove anchor from URL for file check
    file_url="$(echo "$url" | sed 's/#.*//')"
    
    # Skip empty after removing anchor
    [[ -z "$file_url" ]] && continue
    
    # Resolve relative path
    target="$file_dir/$file_url"
    
    # Check if target exists (file or directory)
    if [[ ! -f "$target" && ! -d "$target" ]]; then
      echo "  BROKEN LINK: $url (in $file)"
      EXIT_CODE=1
    fi
  done
done < <(find "$ROOT_DIR" -name "*.md" -print0)

if [[ $EXIT_CODE -eq 0 ]]; then
  echo "PASS: No broken internal links found"
else
  echo "FAIL: Broken links found"
fi

exit $EXIT_CODE
