#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"
QUEUE_STATUS_BIN="${FLOW_ROOT}/tools/bin/resident-issue-queue-status.py"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_dir="${tmpdir}/profiles/demo"
state_root="${tmpdir}/runtime/demo/state"
config_yaml="${profile_dir}/control-plane.yaml"
snapshot_file="${tmpdir}/queue.json"

mkdir -p "${profile_dir}" "${state_root}"

cat >"${config_yaml}" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "${tmpdir}/repo"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo"
  worktree_root: "${tmpdir}/worktrees"
  agent_repo_root: "${tmpdir}/repo"
  runs_root: "${tmpdir}/runtime/demo/runs"
  state_root: "${state_root}"
  history_root: "${tmpdir}/runtime/demo/history"
  retained_repo_root: "${tmpdir}/repo"
  vscode_workspace_file: "${tmpdir}/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
EOF

# shellcheck source=/dev/null
source "${FLOW_CONFIG_LIB}"
# shellcheck source=/dev/null
source "${FLOW_RESIDENT_LIB}"

flow_resident_issue_enqueue "${config_yaml}" "42" "heartbeat" >/dev/null
claim_output="$(flow_resident_issue_claim_next "${config_yaml}" "demo-session-42")"
claim_file="$(awk -F= '/^CLAIM_FILE=/{print substr($0, index($0, "=") + 1); exit}' <<<"${claim_output}")"

[[ -n "${claim_file}" ]]
[[ "${claim_file}" == *.env ]]
[[ -f "${claim_file}" ]]

legacy_claim_file="${state_root}/resident-workers/issue-queue/claims/issue-43.legacy-session.999"
cat >"${legacy_claim_file}" <<'EOF'
ISSUE_ID=43
SESSION=legacy-session
CLAIMED_BY=legacy-session
CLAIMED_AT=2026-03-27T12:00:00Z
EOF

python3 "${QUEUE_STATUS_BIN}" --state-root "${state_root}" >"${snapshot_file}"

python3 - "${snapshot_file}" "${claim_file}" "${legacy_claim_file}" <<'PY'
import json
import sys

snapshot_path, expected_claim_file, legacy_claim_file = sys.argv[1:4]
snapshot = json.load(open(snapshot_path, encoding="utf-8"))

assert snapshot["pending"] == [], snapshot
claims = {item["issue_id"]: item for item in snapshot["claims"]}

assert claims["42"]["session"] == "demo-session-42", claims["42"]
assert claims["42"]["claim_file"] == expected_claim_file, claims["42"]
assert claims["42"]["state_kind"] == "claim", claims["42"]
assert claims["42"]["state_format_version"] == "1", claims["42"]

assert claims["43"]["session"] == "legacy-session", claims["43"]
assert claims["43"]["claim_file"] == legacy_claim_file, claims["43"]
assert claims["43"]["claimed_by"] == "legacy-session", claims["43"]
PY

echo "resident issue queue status contract test passed"
