#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../tools/bin/flow-config-lib.sh"

ISSUE_ID="${1:?usage: issue-resource-class.sh ISSUE_ID}"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"

ISSUE_JSON="$(gh issue view "$ISSUE_ID" -R "$REPO_SLUG" --json number,title,body,labels)"

CLASS_OUT="$(
  ISSUE_JSON="$ISSUE_JSON" python3 <<'PY'
import json
import os
import re

issue = json.loads(os.environ["ISSUE_JSON"])
labels = {str(label.get("name", "")).strip().lower() for label in issue.get("labels", [])}
title = str(issue.get("title", "") or "")
body = str(issue.get("body", "") or "")

explicit_e2e_labels = {
    "agent-e2e-heavy",
    "e2e",
    "playwright",
    "detox",
    "maestro",
}
title_pattern = re.compile(
    r"(^|[^a-z0-9])(e2e|end-to-end|end to end|playwright|detox|maestro)([^a-z0-9]|$)",
    re.IGNORECASE,
)
body_pattern = re.compile(
    r"(^|[^a-z0-9])("
    r"playwright|detox|maestro|"
    r"e2e([ -]+(test|tests|smoke|suite|run|runs|flaky|flake|spec))|"
    r"end-to-end([ -]+(test|tests|smoke|suite|run|runs|flaky|flake|spec))"
    r")([^a-z0-9]|$)",
    re.IGNORECASE,
)

is_e2e = (
    bool(labels.intersection(explicit_e2e_labels))
    or bool(title_pattern.search(title))
    or bool(body_pattern.search(body))
)
issue_class = "e2e-heavy" if is_e2e else "standard"

print(f"CLASS={issue_class}")
print(f"IS_E2E={'yes' if is_e2e else 'no'}")
PY
)"

printf 'ISSUE_ID=%s\n' "$ISSUE_ID"
printf '%s\n' "$CLASS_OUT"
