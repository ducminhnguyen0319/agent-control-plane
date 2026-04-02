#!/usr/bin/env bash
set -euo pipefail

TOOL_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${TOOL_BIN_DIR}/../.." && pwd)"
ROOT_RUNTIME_DIR="${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}/runtime-home"
ROOT_SOURCE_DIR=""

read_runtime_stamp_value() {
  local key="${1:?key required}"
  local stamp_file="${ROOT_RUNTIME_DIR}/.agent-control-plane-runtime-sync.env"
  [[ -f "${stamp_file}" ]] || return 1
  awk -F= -v target="${key}" '$1 == target {print $2; exit}' "${stamp_file}" 2>/dev/null \
    | sed -e "s/^'//" -e "s/'$//"
}

ROOT_SOURCE_DIR="${AGENT_FLOW_SOURCE_HOME:-${ACP_RUNTIME_SYNC_SOURCE_HOME:-}}"
if [[ -z "${ROOT_SOURCE_DIR}" ]]; then
  ROOT_SOURCE_DIR="$(read_runtime_stamp_value "SOURCE_HOME" || true)"
fi
if [[ -z "${ROOT_SOURCE_DIR}" ]]; then
  ROOT_SOURCE_DIR="$(cd "${SKILL_ROOT}/../../.." && pwd)"
fi
if [[ ! -f "${ROOT_SOURCE_DIR}/tools/bin/agent-project-reconcile-pr-session" ]]; then
  ROOT_SOURCE_DIR="${SKILL_ROOT}"
fi
HAS_DISTINCT_ROOT_SOURCE=0
if [[ "${ROOT_SOURCE_DIR}" != "${SKILL_ROOT}" ]]; then
  HAS_DISTINCT_ROOT_SOURCE=1
fi
RUNTIME_SKILL_ROOT="${ROOT_RUNTIME_DIR}/skills/openclaw/agent-control-plane"
# shellcheck source=/dev/null
source "${TOOL_BIN_DIR}/flow-config-lib.sh"
failures=0

contains_fixed_string() {
  local pattern="${1:?pattern required}"
  local file="${2:?file required}"
  if command -v rg >/dev/null 2>&1; then
    rg -q --fixed-strings -- "$pattern" "$file"
  else
    grep -F -q -- "$pattern" "$file"
  fi
}

check_contains() {
  local file="${1:?file required}"
  local pattern="${2:?pattern required}"
  local label="${3:?label required}"
  if contains_fixed_string "$pattern" "$file"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (%s missing in %s)\n' "$label" "$pattern" "$file" >&2
    failures=$((failures + 1))
  fi
}

check_absent() {
  local file="${1:?file required}"
  local pattern="${2:?pattern required}"
  local label="${3:?label required}"
  if contains_fixed_string "$pattern" "$file"; then
    printf 'FAIL %s (%s unexpectedly present in %s)\n' "$label" "$pattern" "$file" >&2
    failures=$((failures + 1))
  else
    printf 'PASS %s\n' "$label"
  fi
}

check_sync_if_present() {
  local source_file="${1:?source file required}"
  local runtime_file="${2:?runtime file required}"
  local label="${3:?label required}"
  if [[ ! -f "$runtime_file" ]]; then
    printf 'SKIP %s (runtime copy missing)\n' "$label"
    return 0
  fi
  if cmp -s "$source_file" "$runtime_file"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (source/runtime drift)\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

issue_template="${SKILL_ROOT}/tools/templates/issue-prompt-template.md"
scheduled_issue_template="${SKILL_ROOT}/tools/templates/scheduled-issue-prompt-template.md"
pr_review_template="${SKILL_ROOT}/tools/templates/pr-review-template.md"
pr_fix_template="${SKILL_ROOT}/tools/templates/pr-fix-template.md"
pr_merge_repair_template="${SKILL_ROOT}/tools/templates/pr-merge-repair-template.md"
legacy_profile_repo_name="$(printf 'f-%s' 'losning')"
legacy_profile_repo_slug="$(printf '%s/%s' 'example-owner' "${legacy_profile_repo_name}")"
legacy_profile_package_scope="@${legacy_profile_repo_name}"
commands_map="${SKILL_ROOT}/references/commands.md"
skill_doc="${SKILL_ROOT}/SKILL.md"
issue_reconcile="${SKILL_ROOT}/tools/bin/agent-project-reconcile-issue-session"
pr_reconcile="${SKILL_ROOT}/tools/bin/agent-project-reconcile-pr-session"
start_issue_worker="${SKILL_ROOT}/tools/bin/start-issue-worker.sh"
start_pr_fix_worker="${SKILL_ROOT}/tools/bin/start-pr-fix-worker.sh"
start_pr_review_worker="${SKILL_ROOT}/tools/bin/start-pr-review-worker.sh"
run_codex_task="${SKILL_ROOT}/tools/bin/run-codex-task.sh"
codex_quota_wrapper="${SKILL_ROOT}/tools/bin/codex-quota"
run_claude_session="${SKILL_ROOT}/tools/bin/agent-project-run-claude-session"
run_openclaw_session="${SKILL_ROOT}/tools/bin/agent-project-run-openclaw-session"
ensure_runtime_sync="${SKILL_ROOT}/tools/bin/ensure-runtime-sync.sh"
run_opencode_session="${SKILL_ROOT}/tools/bin/agent-project-run-opencode-session"
run_kilo_session="${SKILL_ROOT}/tools/bin/agent-project-run-kilo-session"
record_verification="${SKILL_ROOT}/tools/bin/record-verification.sh"
branch_verification_guard="${SKILL_ROOT}/tools/bin/branch-verification-guard.sh"
workflow_catalog="${SKILL_ROOT}/assets/workflow-catalog.json"
workflow_catalog_script="${SKILL_ROOT}/tools/bin/workflow-catalog.sh"
flow_runtime_doctor="${SKILL_ROOT}/tools/bin/flow-runtime-doctor.sh"
flow_config_lib="${SKILL_ROOT}/tools/bin/flow-config-lib.sh"
render_flow_config="${SKILL_ROOT}/tools/bin/render-flow-config.sh"
scaffold_profile="${SKILL_ROOT}/tools/bin/scaffold-profile.sh"
project_init="${SKILL_ROOT}/tools/bin/project-init.sh"
project_remove="${SKILL_ROOT}/tools/bin/project-remove.sh"
profile_smoke="${SKILL_ROOT}/tools/bin/profile-smoke.sh"
test_smoke="${SKILL_ROOT}/tools/bin/test-smoke.sh"
profile_adopt="${SKILL_ROOT}/tools/bin/profile-adopt.sh"
profile_activate="${SKILL_ROOT}/tools/bin/profile-activate.sh"
project_runtimectl="${SKILL_ROOT}/tools/bin/project-runtimectl.sh"
project_launchd_bootstrap="${SKILL_ROOT}/tools/bin/project-launchd-bootstrap.sh"
project_launchd_install="${SKILL_ROOT}/tools/bin/install-project-launchd.sh"
project_launchd_uninstall="${SKILL_ROOT}/tools/bin/uninstall-project-launchd.sh"
provider_cooldown_state="${SKILL_ROOT}/tools/bin/provider-cooldown-state.sh"
dashboard_launchd_bootstrap="${SKILL_ROOT}/tools/bin/dashboard-launchd-bootstrap.sh"
dashboard_launchd_install="${SKILL_ROOT}/tools/bin/install-dashboard-launchd.sh"
compat_skill_alias="$(flow_compat_skill_alias)"
root_pr_reconcile="${ROOT_SOURCE_DIR}/tools/bin/agent-project-reconcile-pr-session"
root_issue_reconcile="${ROOT_SOURCE_DIR}/tools/bin/agent-project-reconcile-issue-session"

check_contains "$issue_template" "ACTION=host-comment-blocker" "core issue template blocked action"
check_contains "$issue_template" "OUTCOME=implemented" "core issue template success outcome"
check_contains "$issue_template" "ACTION=host-publish-issue-pr" "core issue template success action"
check_contains "$issue_template" "{ISSUE_RECURRING_CONTEXT}" "core issue template recurring context placeholder"
check_contains "$issue_template" "record-verification.sh" "core issue template verification journal guidance"
check_contains "$issue_template" "verification.jsonl" "core issue template verification journal contract"
check_contains "$issue_template" "Superseded by focused follow-up issues:" "core issue template umbrella supersede marker"
check_contains "$issue_template" "create-follow-up-issue.sh" "core issue template follow-up helper guidance"
check_contains "$issue_template" '`{REPO_SLUG}`' "core issue template repo slug placeholder"
check_contains "$issue_template" '$ACP_FLOW_TOOLS_DIR' "core issue template canonical tools env"
check_absent "$issue_template" "${legacy_profile_package_scope}" "core issue template removed bundled package refs"
check_contains "$scheduled_issue_template" "host-comment-scheduled-report" "core scheduled issue template report action"
check_contains "$scheduled_issue_template" "host-comment-scheduled-alert" "core scheduled issue template alert action"
check_contains "$scheduled_issue_template" "not an implementation cycle" "core scheduled issue template check-only guidance"
check_contains "$scheduled_issue_template" "{ISSUE_BASELINE_HEAD_SHA}" "core scheduled issue template fixed baseline sha guidance"
check_contains "$scheduled_issue_template" '`{REPO_SLUG}`' "core scheduled issue template repo slug placeholder"
check_absent "$scheduled_issue_template" "${legacy_profile_repo_slug}" "core scheduled issue template removed bundled repo slug"
check_contains "$pr_review_template" "ACTION=host-advance-double-check-2" "core review template stage-1 action"
check_contains "$pr_review_template" "ACTION=host-approve-and-merge" "core review template merge action"
check_contains "$pr_review_template" "ACTION=host-await-human-review" "core review template human-review action"
check_contains "$pr_review_template" '`{REPO_SLUG}`' "core review template repo slug placeholder"
check_absent "$pr_review_template" "${legacy_profile_package_scope}" "core review template removed bundled package refs"
check_contains "$pr_fix_template" "did not run Git commit/push commands yourself" "core fix template host-owned git contract"
check_contains "$pr_fix_template" "record-verification.sh" "core fix template verification journal guidance"
check_contains "$pr_fix_template" "verification.jsonl" "core fix template verification journal contract"
check_contains "$pr_fix_template" "Required targeted verification coverage before" "core fix template targeted verification section"
check_contains "$pr_fix_template" '`{REPO_SLUG}`' "core fix template repo slug placeholder"
check_absent "$pr_fix_template" "If you fixed the branch and committed locally" "core fix template removed local-commit wording"
check_contains "$pr_merge_repair_template" "record-verification.sh" "core merge-repair template verification journal guidance"
check_contains "$pr_merge_repair_template" "verification.jsonl" "core merge-repair template verification journal contract"
check_contains "$pr_merge_repair_template" '`{REPO_SLUG}`' "core merge-repair template repo slug placeholder"
check_contains "$commands_map" "## Dependency bootstrap" "commands map bootstrap section"
check_contains "$commands_map" "## Flow maintenance" "commands map flow maintenance section"
check_contains "$commands_map" "~/.agent-runtime/control-plane/profiles/<id>/README.md" "commands map profile readme note"
check_contains "$skill_doc" "openspec/CONVENTIONS.md" "skill startup reads conventions"
check_contains "$skill_doc" "~/.agent-runtime/control-plane/profiles/<id>/README.md" "skill profile readme routing"
check_contains "$skill_doc" "agent-control-plane" "skill doc control plane rename"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "assets/workflow-catalog.json" "control plane map workflow catalog"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "flow-runtime-doctor.sh" "control plane map runtime doctor"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "render-flow-config.sh" "control plane map render flow config"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "project-init.sh" "control plane map project init"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "scaffold-profile.sh" "control plane map scaffold profile"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "project-runtimectl.sh" "control plane map project runtimectl"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "project-launchd-bootstrap.sh" "control plane map project launchd bootstrap"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "install-project-launchd.sh" "control plane map project launchd install"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "uninstall-project-launchd.sh" "control plane map project launchd uninstall"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "project-remove.sh" "control plane map project remove"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "profile-smoke.sh" "control plane map profile smoke"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "test-smoke.sh" "control plane map test smoke"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "profile-adopt.sh" "control plane map profile adopt"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "~/.agent-runtime/control-plane/profiles/<id>/control-plane.yaml" "control plane map canonical profile"
check_contains "${SKILL_ROOT}/references/control-plane-map.md" "~/.agent-runtime/control-plane/profiles/<id>/README.md" "control plane map profile notes"
check_contains "$issue_reconcile" "host-comment-blocker" "issue reconcile blocked contract"
check_contains "$issue_reconcile" "implemented:host-publish-issue-pr" "issue reconcile success contract"
check_contains "$issue_reconcile" "closed-superseded" "issue reconcile umbrella supersede contract"
check_contains "$issue_reconcile" "reported:host-comment-scheduled-report" "issue reconcile scheduled report contract"
check_contains "$issue_reconcile" "reported:host-comment-scheduled-alert" "issue reconcile scheduled alert contract"
check_contains "$pr_reconcile" "host-advance-double-check-2" "pr reconcile stage-1 contract"
check_contains "$pr_reconcile" "host-await-human-review" "pr reconcile human-review contract"
check_contains "$pr_reconcile" "host-verification-guard-blocked" "pr reconcile verification-guard blocked contract"
check_contains "$start_issue_worker" "Opened PR #" "start issue worker parses recurring PR history"
check_contains "$start_issue_worker" "Target:" "start issue worker recurring target guidance"
check_contains "$start_issue_worker" "Blocked on missing referenced OpenSpec paths for issue #" "start issue worker missing-openspec guard"
check_contains "$start_issue_worker" "scheduled-issue-prompt-template.md" "start issue worker scheduled template switch"
check_contains "$start_issue_worker" "ISSUE_BASELINE_HEAD_SHA" "start issue worker baseline sha prompt context"
check_contains "$start_issue_worker" "flow_resolve_template_file" "start issue worker template resolver"
check_contains "$start_pr_fix_worker" "flow_resolve_template_file" "start pr fix worker template resolver"
check_contains "$start_pr_fix_worker" "flow_resolve_web_playwright_command" "start pr fix worker playwright command resolver"
check_contains "$start_pr_review_worker" "flow_resolve_template_file" "start pr review worker template resolver"
check_contains "$start_issue_worker" "Blocked retries so far:" "start issue worker blocked retry context"
check_absent "$pr_reconcile" "legacy-empty-result-contract" "pr reconcile removed empty-result compatibility"
if (( HAS_DISTINCT_ROOT_SOURCE )); then
  check_contains "$root_pr_reconcile" "host-advance-double-check-2" "root pr reconcile stage-1 contract"
  check_contains "$root_issue_reconcile" "host-comment-blocker" "root issue reconcile blocked contract"
  check_contains "$root_issue_reconcile" "implemented:host-publish-issue-pr" "root issue reconcile success contract"
  check_absent "$root_pr_reconcile" "legacy-empty-result-contract" "root pr reconcile removed empty-result compatibility"
fi
check_contains "$run_codex_task" "--collect-file \"verification.jsonl\"" "run task collects verification journal"
check_contains "$run_codex_task" "FLOW_TOOLS_DIR" "run task exports flow tools dir"
check_contains "$issue_template" '`{REPO_SLUG}`' "issue template repo slug placeholder"
check_contains "$issue_template" '$ACP_FLOW_TOOLS_DIR' "issue template canonical tools env"
check_contains "$pr_fix_template" '`{REPO_SLUG}`' "fix template repo slug placeholder"
check_contains "$pr_review_template" '`{REPO_SLUG}`' "review template repo slug placeholder"
check_contains "$pr_merge_repair_template" '`{REPO_SLUG}`' "merge-repair template repo slug placeholder"
check_contains "$run_codex_task" "agent-project-run-openclaw-session" "run task openclaw dispatch"
check_contains "$run_codex_task" "agent-project-run-claude-session" "run task claude dispatch"
check_contains "$run_codex_task" "agent-project-run-opencode-session" "run task opencode dispatch"
check_contains "$run_codex_task" "agent-project-run-kilo-session" "run task kilo dispatch"
check_contains "$codex_quota_wrapper" "vendor/codex-quota/codex-quota.js" "codex quota wrapper vendored entrypoint"
  check_contains "$run_claude_session" "install_pre_commit_scope_hook" "claude session installs pre-commit scope hook"
check_contains "$run_claude_session" "run_with_timeout" "claude session timeout helper"
check_contains "$run_openclaw_session" "OPENCLAW_CONFIG_PATH" "openclaw session isolated config contract"
check_contains "$run_openclaw_session" "SOUL.md" "openclaw session ignore bootstrap files"
check_contains "$run_opencode_session" "execution is not implemented yet" "opencode placeholder adapter contract"
check_contains "$run_kilo_session" "execution is not implemented yet" "kilo placeholder adapter contract"
check_contains "$flow_config_lib" "flow_export_execution_env" "flow config lib exports execution env"
check_contains "$flow_config_lib" "flow_resolve_provider_quota_cooldowns" "flow config lib provider quota cooldown resolver"
check_contains "$flow_config_lib" "flow_selected_provider_pool_env" "flow config lib provider pool selection helper"
check_contains "$flow_config_lib" "flow_resolve_codex_quota_bin" "flow config lib codex quota bin resolver"
check_contains "$flow_config_lib" "flow_resolve_codex_quota_manager_script" "flow config lib codex quota manager resolver"
check_contains "$render_flow_config" "EFFECTIVE_CODING_WORKER=" "render flow config coding worker output"
check_contains "$render_flow_config" "EFFECTIVE_PROVIDER_QUOTA_COOLDOWNS=" "render flow config provider quota cooldown output"
check_contains "$render_flow_config" "EFFECTIVE_PROVIDER_POOL_NAME=" "render flow config active provider pool output"
check_contains "$render_flow_config" "EFFECTIVE_AGENT_REPO_ROOT=" "render flow config agent repo output"
check_contains "$render_flow_config" "PROFILE_ID=" "render flow config profile id output"
check_contains "$render_flow_config" "PROFILE_REGISTRY_ROOT=" "render flow config profile registry output"
check_contains "$render_flow_config" "PROFILE_SELECTION_MODE=" "render flow config selection mode output"
check_contains "$render_flow_config" "PROFILE_NOTES=" "render flow config profile notes output"
check_contains "$commands_map" "tools/bin/workflow-catalog.sh context" "commands map workflow catalog context command"
check_contains "$commands_map" "tools/bin/profile-activate.sh --profile-id <id>" "commands map profile activate command"
check_contains "$commands_map" "tools/bin/project-init.sh --profile-id <id> --repo-slug <owner/repo>" "commands map project init command"
check_contains "$commands_map" "tools/bin/scaffold-profile.sh" "commands map scaffold profile command"
check_contains "$commands_map" "tools/bin/profile-smoke.sh" "commands map profile smoke command"
check_contains "$commands_map" "tools/bin/test-smoke.sh" "commands map test smoke command"
check_contains "$commands_map" "tools/bin/profile-adopt.sh" "commands map profile adopt command"
check_contains "$commands_map" "tools/bin/project-runtimectl.sh status --profile-id <id>" "commands map project runtimectl status command"
check_contains "$commands_map" "tools/bin/project-runtimectl.sh sync --profile-id <id>" "commands map project runtimectl sync command"
check_contains "$commands_map" "tools/bin/project-remove.sh --profile-id <id>" "commands map project remove command"
check_contains "$commands_map" "tools/bin/install-project-launchd.sh --profile-id <id>" "commands map project launchd install command"
check_contains "$commands_map" "tools/bin/uninstall-project-launchd.sh --profile-id <id>" "commands map project launchd uninstall command"
check_contains "$commands_map" "tools/bin/install-dashboard-launchd.sh" "commands map dashboard launchd install command"
check_contains "$commands_map" "~/.agent-runtime/control-plane/profiles/<id>/templates/" "commands map profile templates note"
check_contains "$project_init" "PROJECT_INIT_STATUS=ok" "project init status output"
check_contains "$project_remove" "PROJECT_REMOVE_STATUS=ok" "project remove status output"
check_contains "$scaffold_profile" "PROFILE_YAML=" "scaffold profile output"
check_contains "$profile_smoke" "PROFILE_SMOKE_STATUS" "profile smoke status output"
check_contains "$test_smoke" "SMOKE_TEST_STATUS" "test smoke status output"
check_contains "$profile_adopt" "ADOPT_STATUS" "profile adopt status output"
check_contains "$profile_activate" "PROFILE_ID=" "profile activate profile output"
check_contains "$profile_activate" "export ACP_PROJECT_ID=" "profile activate exports output"
check_contains "$project_runtimectl" "ACTION=start" "project runtimectl start output"
check_contains "$project_runtimectl" "ACTION=stop" "project runtimectl stop output"
check_contains "$project_runtimectl" "ACTION=sync" "project runtimectl sync output"
check_contains "$project_runtimectl" "RUNTIME_STATUS=" "project runtimectl status output"
check_contains "$project_runtimectl" "RUNTIME_SYNC_STATUS=" "project runtimectl sync status output"
check_contains "$project_launchd_bootstrap" "heartbeat-safe-auto.sh" "project launchd bootstrap heartbeat contract"
check_contains "$project_launchd_bootstrap" "sync-shared-agent-home.sh" "project launchd bootstrap sync contract"
check_contains "$project_launchd_bootstrap" "ensure-runtime-sync.sh" "project launchd bootstrap ensure sync contract"
check_contains "$project_launchd_install" "project-runtime-supervisor.sh" "project launchd install supervisor contract"
check_contains "$project_launchd_install" "launchctl bootstrap" "project launchd install bootstrap command"
check_contains "$project_launchd_uninstall" "launchctl bootout" "project launchd uninstall bootout command"
check_contains "$workflow_catalog_script" "assets/workflow-catalog.json" "workflow catalog script reads catalog file"
check_contains "$workflow_catalog_script" 'if command == "context":' "workflow catalog context command"
check_contains "$flow_runtime_doctor" "DOCTOR_STATUS" "runtime doctor status output"
check_contains "$flow_runtime_doctor" "PROFILE_REGISTRY_ROOT" "runtime doctor profile registry output"
check_contains "$flow_runtime_doctor" "PROFILE_SELECTION_MODE" "runtime doctor selection mode output"
check_contains "$flow_runtime_doctor" "PROFILE_NOTES" "runtime doctor profile notes output"
check_contains "$flow_runtime_doctor" "NEXT_STEP=" "runtime doctor next step output"
check_contains "$flow_runtime_doctor" "CONTROL_PLANE_NAME" "runtime doctor canonical name output"
check_contains "$dashboard_launchd_bootstrap" "sync-shared-agent-home.sh" "dashboard launchd bootstrap sync runtime contract"
check_contains "$dashboard_launchd_bootstrap" "ensure-runtime-sync.sh" "dashboard launchd bootstrap ensure sync contract"
check_contains "$dashboard_launchd_bootstrap" "serve-dashboard.sh" "dashboard launchd bootstrap serve contract"
check_contains "$dashboard_launchd_install" "launchctl bootstrap" "dashboard launchd install bootstrap command"
check_contains "$dashboard_launchd_install" "<key>KeepAlive</key>" "dashboard launchd install keepalive contract"
check_absent "$skill_doc" 'repo-local `profiles/<id>/`' "skill doc removed repo-bundled profiles"
check_absent "$commands_map" 'bundled `profiles/<id>/templates/`' "commands map removed bundled profile templates"
check_absent "${SKILL_ROOT}/references/control-plane-map.md" 'bundled `profiles/<id>/`' "control plane map removed bundled profiles"
check_absent "${SKILL_ROOT}/references/repo-map.md" '- `profiles/`' "repo map removed bundled profiles dir"
check_absent "${SKILL_ROOT}/references/docs-map.md" "Bundled seed/fallback profiles" "docs map removed repo-bundled profiles"

if [[ -n "${compat_skill_alias}" ]]; then
  check_absent "$pr_reconcile" "skills/openclaw/${compat_skill_alias}" "skill pr reconcile removed old package fallback"
  if (( HAS_DISTINCT_ROOT_SOURCE )); then
    check_absent "$root_pr_reconcile" "skills/openclaw/${compat_skill_alias}" "root pr reconcile removed old package fallback"
  fi
fi

check_sync_if_present "$issue_template" "${RUNTIME_SKILL_ROOT}/tools/templates/issue-prompt-template.md" "core issue template source/runtime sync"
check_sync_if_present "$scheduled_issue_template" "${RUNTIME_SKILL_ROOT}/tools/templates/scheduled-issue-prompt-template.md" "core scheduled issue template source/runtime sync"
check_sync_if_present "$pr_review_template" "${RUNTIME_SKILL_ROOT}/tools/templates/pr-review-template.md" "core review template source/runtime sync"
check_sync_if_present "$pr_fix_template" "${RUNTIME_SKILL_ROOT}/tools/templates/pr-fix-template.md" "core fix template source/runtime sync"
check_sync_if_present "$pr_merge_repair_template" "${RUNTIME_SKILL_ROOT}/tools/templates/pr-merge-repair-template.md" "core merge-repair template source/runtime sync"
check_sync_if_present "$commands_map" "${RUNTIME_SKILL_ROOT}/references/commands.md" "commands map source/runtime sync"
check_sync_if_present "$pr_reconcile" "${RUNTIME_SKILL_ROOT}/tools/bin/agent-project-reconcile-pr-session" "skill pr reconcile source/runtime sync"
check_sync_if_present "$issue_reconcile" "${RUNTIME_SKILL_ROOT}/tools/bin/agent-project-reconcile-issue-session" "skill issue reconcile source/runtime sync"
check_sync_if_present "$start_issue_worker" "${RUNTIME_SKILL_ROOT}/tools/bin/start-issue-worker.sh" "start issue worker source/runtime sync"
check_sync_if_present "$run_codex_task" "${RUNTIME_SKILL_ROOT}/tools/bin/run-codex-task.sh" "run task source/runtime sync"
check_sync_if_present "$codex_quota_wrapper" "${RUNTIME_SKILL_ROOT}/tools/bin/codex-quota" "codex quota wrapper source/runtime sync"
check_sync_if_present "$run_claude_session" "${RUNTIME_SKILL_ROOT}/tools/bin/agent-project-run-claude-session" "claude session source/runtime sync"
check_sync_if_present "$run_openclaw_session" "${RUNTIME_SKILL_ROOT}/tools/bin/agent-project-run-openclaw-session" "openclaw session source/runtime sync"
check_sync_if_present "$ensure_runtime_sync" "${RUNTIME_SKILL_ROOT}/tools/bin/ensure-runtime-sync.sh" "ensure runtime sync source/runtime sync"
check_sync_if_present "$run_opencode_session" "${RUNTIME_SKILL_ROOT}/tools/bin/agent-project-run-opencode-session" "opencode session source/runtime sync"
check_sync_if_present "$run_kilo_session" "${RUNTIME_SKILL_ROOT}/tools/bin/agent-project-run-kilo-session" "kilo session source/runtime sync"
check_sync_if_present "$record_verification" "${RUNTIME_SKILL_ROOT}/tools/bin/record-verification.sh" "record verification source/runtime sync"
check_sync_if_present "$branch_verification_guard" "${RUNTIME_SKILL_ROOT}/tools/bin/branch-verification-guard.sh" "branch verification guard source/runtime sync"
check_sync_if_present "$flow_config_lib" "${RUNTIME_SKILL_ROOT}/tools/bin/flow-config-lib.sh" "flow config lib source/runtime sync"
check_sync_if_present "$render_flow_config" "${RUNTIME_SKILL_ROOT}/tools/bin/render-flow-config.sh" "render flow config source/runtime sync"
check_sync_if_present "$provider_cooldown_state" "${RUNTIME_SKILL_ROOT}/tools/bin/provider-cooldown-state.sh" "provider cooldown state source/runtime sync"
check_sync_if_present "$project_init" "${RUNTIME_SKILL_ROOT}/tools/bin/project-init.sh" "project init source/runtime sync"
check_sync_if_present "$project_remove" "${RUNTIME_SKILL_ROOT}/tools/bin/project-remove.sh" "project remove source/runtime sync"
check_sync_if_present "$project_launchd_bootstrap" "${RUNTIME_SKILL_ROOT}/tools/bin/project-launchd-bootstrap.sh" "project launchd bootstrap source/runtime sync"
check_sync_if_present "$project_launchd_install" "${RUNTIME_SKILL_ROOT}/tools/bin/install-project-launchd.sh" "project launchd install source/runtime sync"
check_sync_if_present "$project_launchd_uninstall" "${RUNTIME_SKILL_ROOT}/tools/bin/uninstall-project-launchd.sh" "project launchd uninstall source/runtime sync"
check_sync_if_present "$scaffold_profile" "${RUNTIME_SKILL_ROOT}/tools/bin/scaffold-profile.sh" "scaffold profile source/runtime sync"
check_sync_if_present "$profile_smoke" "${RUNTIME_SKILL_ROOT}/tools/bin/profile-smoke.sh" "profile smoke source/runtime sync"
check_sync_if_present "$test_smoke" "${RUNTIME_SKILL_ROOT}/tools/bin/test-smoke.sh" "test smoke source/runtime sync"
check_sync_if_present "$profile_adopt" "${RUNTIME_SKILL_ROOT}/tools/bin/profile-adopt.sh" "profile adopt source/runtime sync"
check_sync_if_present "$profile_activate" "${RUNTIME_SKILL_ROOT}/tools/bin/profile-activate.sh" "profile activate source/runtime sync"
check_sync_if_present "$project_runtimectl" "${RUNTIME_SKILL_ROOT}/tools/bin/project-runtimectl.sh" "project runtimectl source/runtime sync"
check_sync_if_present "$dashboard_launchd_bootstrap" "${RUNTIME_SKILL_ROOT}/tools/bin/dashboard-launchd-bootstrap.sh" "dashboard launchd bootstrap source/runtime sync"
check_sync_if_present "$dashboard_launchd_install" "${RUNTIME_SKILL_ROOT}/tools/bin/install-dashboard-launchd.sh" "dashboard launchd install source/runtime sync"
check_sync_if_present "$workflow_catalog" "${RUNTIME_SKILL_ROOT}/assets/workflow-catalog.json" "workflow catalog source/runtime sync"
check_sync_if_present "$workflow_catalog_script" "${RUNTIME_SKILL_ROOT}/tools/bin/workflow-catalog.sh" "workflow catalog script source/runtime sync"
check_sync_if_present "$flow_runtime_doctor" "${RUNTIME_SKILL_ROOT}/tools/bin/flow-runtime-doctor.sh" "runtime doctor source/runtime sync"
if (( HAS_DISTINCT_ROOT_SOURCE )); then
  check_sync_if_present "$root_pr_reconcile" "${ROOT_RUNTIME_DIR}/tools/bin/agent-project-reconcile-pr-session" "root pr reconcile source/runtime sync"
  check_sync_if_present "$root_issue_reconcile" "${ROOT_RUNTIME_DIR}/tools/bin/agent-project-reconcile-issue-session" "root issue reconcile source/runtime sync"
fi

if (( failures > 0 )); then
  printf 'CHECK_STATUS=failed\n'
  exit 1
fi

printf 'CHECK_STATUS=ok\n'
