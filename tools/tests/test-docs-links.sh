#!/usr/bin/env bash
# test-docs-links.sh
# Simple check for broken internal links in markdown files

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXIT_CODE=0

echo "Checking for broken internal links in markdown files..."

# Find all markdown files
while IFS= read -r -d '' file; do
  # Get directory of the file for resolving relative links
  file_dir="$(dirname "$file")"
  
  # Extract markdown links using grep
  # Pattern: [text](url)
  grep -o '\[[^]]*\]([^)]*)' "$file" 2>/dev/null | while IFS= read -r match; do
    # Extract URL from [text](url)
    url="$(echo "$match" | sed 's/.*(//;s/)$//')"
    
    # Skip external links
    if [[ "$url" =~ ^https?:// ]]; then
      continue
    fi
    
    # Skip anchor links
    if [[ "$url" =~ ^# ]]; then
      continue
    fi
    
    # Remove anchor from URL for file check
    file_url="$(echo "$url" | sed 's/#.*//')"
    
    # Resolve relative path
    target="$file_dir/$file_url"
    
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
