#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
fake_bin="${tmpdir}/bin"
update_log="${tmpdir}/update.log"

mkdir -p "${profile_dir}" "${fake_bin}" "${tmpdir}/repo" "${tmpdir}/runtime/demo"

cat >"${profile_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "${tmpdir}/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo"
  worktree_root: "${tmpdir}/worktrees"
  agent_repo_root: "${tmpdir}/repo"
  runs_root: "${tmpdir}/runtime/demo/runs"
  state_root: "${tmpdir}/runtime/demo/state"
  history_root: "${tmpdir}/runtime/demo/history"
  retained_repo_root: "${tmpdir}/repo"
  vscode_workspace_file: "${tmpdir}/demo.code-workspace"
execution:
  coding_worker: "openclaw"
EOF

cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  printf '[{"number":1,"labels":[{"name":"agent-running"}]},{"number":2,"labels":[{"name":"agent-keep-open"}]}]\n'
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  printf '[{"number":7,"labels":[{"name":"agent-running"}]}]\n'
  exit 0
fi

exit 64
EOF
chmod +x "${fake_bin}/gh"

cat >"${fake_bin}/update-labels.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${update_log}"
EOF
chmod +x "${fake_bin}/update-labels.sh"

output="$(
  PATH="${fake_bin}:$PATH" \
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
  ACP_PROJECT_RUNTIME_UPDATE_LABELS_SCRIPT="${fake_bin}/update-labels.sh" \
    bash "${RUNTIMECTL_BIN}" stop --profile-id demo
)"

grep -q 'ACTION=stop' <<<"${output}"
grep -q '^--repo-slug example/demo --number 1 --remove agent-running$' "${update_log}"
grep -q '^--repo-slug example/demo --number 7 --remove agent-running$' "${update_log}"
if grep -q '^--repo-slug example/demo --number 2 --remove agent-running$' "${update_log}"; then
  echo "non-running issue label update should not be attempted" >&2
  exit 1
fi

echo "project runtimectl stop clears running labels test passed"
