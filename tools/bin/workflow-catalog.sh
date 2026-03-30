#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
CATALOG_FILE="${FLOW_SKILL_DIR}/assets/workflow-catalog.json"
COMMAND="${1:-list}"
WORKFLOW_ID="${2:-}"
AVAILABLE_PROFILES="$(flow_list_profile_ids "${FLOW_SKILL_DIR}" | paste -sd, -)"
ACTIVE_PROFILE="$(flow_resolve_adapter_id "$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")")"
PROFILE_SELECTION_MODE="$(flow_profile_selection_mode "${FLOW_SKILL_DIR}")"
PROFILE_NOTES="$(flow_resolve_profile_notes_file "$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")")"

python3 - "$CATALOG_FILE" "$COMMAND" "$WORKFLOW_ID" "$AVAILABLE_PROFILES" "$ACTIVE_PROFILE" "$PROFILE_SELECTION_MODE" "$PROFILE_NOTES" <<'PY'
import json
import sys

catalog_file, command, workflow_id, available_profiles, active_profile, profile_selection_mode, profile_notes = sys.argv[1:8]
with open(catalog_file, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

workflows = payload.get("workflows", [])
profile_ids = [item for item in available_profiles.split(",") if item]

if profile_ids:
    payload["available_profiles"] = profile_ids

payload["active_profile"] = active_profile
payload["profile_selection_mode"] = profile_selection_mode
payload["profile_notes"] = profile_notes

if command == "json":
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    raise SystemExit(0)

if command == "profiles":
    for profile_id in profile_ids:
        sys.stdout.write(f"{profile_id}\n")
    raise SystemExit(0)

if command == "ids":
    for workflow in workflows:
        sys.stdout.write(f"{workflow['id']}\n")
    raise SystemExit(0)

if command == "context":
    sys.stdout.write(f"ACTIVE_PROFILE={active_profile}\n")
    sys.stdout.write(f"PROFILE_SELECTION_MODE={profile_selection_mode}\n")
    sys.stdout.write(f"PROFILE_NOTES={profile_notes}\n")
    raise SystemExit(0)

if command == "show":
    match = next((wf for wf in workflows if wf["id"] == workflow_id), None)
    if match is None:
      raise SystemExit(f"unknown workflow id: {workflow_id}")
    sys.stdout.write(f"ACTIVE_PROFILE={active_profile}\n")
    sys.stdout.write(f"PROFILE_SELECTION_MODE={profile_selection_mode}\n")
    for key in ("id", "kind", "trigger", "entrypoint", "summary"):
        sys.stdout.write(f"{key.upper()}={match.get(key, '')}\n")
    raise SystemExit(0)

if command != "list":
    raise SystemExit(f"unknown command: {command}")

for workflow in workflows:
    row = [
        workflow.get("id", ""),
        workflow.get("kind", ""),
        workflow.get("entrypoint", ""),
        workflow.get("trigger", ""),
    ]
    sys.stdout.write("\t".join(row) + "\n")
PY
