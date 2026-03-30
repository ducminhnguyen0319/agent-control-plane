#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

NUMBER="${1:?usage: update-github-labels.sh NUMBER [--add LABEL]... [--remove LABEL]...}"
shift
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
UPDATE_LABELS_BIN="${SCRIPT_DIR}/agent-github-update-labels"

bash "${UPDATE_LABELS_BIN}" --repo-slug "$REPO_SLUG" --number "$NUMBER" "$@"
