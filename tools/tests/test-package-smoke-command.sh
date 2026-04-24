#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  test-package-smoke-command.sh [--help]

Run the main smoke gates for the packaged agent-control-plane command.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

cd "${FLOW_ROOT}"

TMP_PACK_DIR=$(mktemp -d)
TMP_HOME=$(mktemp -d)
TMP_PLATFORM=$(mktemp -d)
TMP_NPM_CACHE=$(mktemp -d)
TMP_OUTPUT=$(mktemp)
cleanup() {
  rm -rf "$TMP_PACK_DIR" "$TMP_HOME" "$TMP_PLATFORM" "$TMP_NPM_CACHE"
  rm -f "$TMP_OUTPUT"
}
trap cleanup EXIT

run_step() {
  local label="${1:?label required}"
  shift
  local status=0

  printf 'SMOKE_STEP=%s\n' "${label}"
  set +e
  "$@"
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    printf 'SMOKE_STEP_STATUS=ok\n'
    return 0
  fi

  printf 'SMOKE_STEP_STATUS=failed\n'
  printf 'FAILED_STEP=%s\n' "${label}"
  printf 'EXIT_CODE=%s\n' "${status}"
  printf 'SMOKE_TEST_STATUS=failed\n'
  return "${status}"
}

NPM_CONFIG_CACHE="${TMP_NPM_CACHE}" \
npm_config_cache="${TMP_NPM_CACHE}" \
npm pack --pack-destination "$TMP_PACK_DIR" >/dev/null
tarball_path=$(printf '%s\n' "$TMP_PACK_DIR"/agent-control-plane-*.tgz)
if [[ ! -f "${tarball_path}" ]]; then
  echo "failed to build package tarball" >&2
  exit 1
fi

run_smoke_command_fixture() (
  set -euo pipefail
  # Install the tarball first, then run
  npm install -g "$tarball_path" 2>/dev/null
  HOME="$TMP_HOME" \
    AGENT_PLATFORM_HOME="$TMP_PLATFORM" \
    NPM_CONFIG_CACHE="$TMP_NPM_CACHE" \
    npm_config_cache="$TMP_NPM_CACHE" \
    agent-control-plane smoke >"$TMP_OUTPUT" 2>&1
  grep -q '^SMOKE_TEST_STATUS=ok$' "$TMP_OUTPUT"
)

run_setup_dry_run_fixture() (
  set -euo pipefail
  local tmpdir=""
  local setup_repo=""
  local output=""

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
  setup_repo="${tmpdir}/setup-demo"
  mkdir -p "${setup_repo}"
  printf '# setup smoke\n' >"${setup_repo}/README.md"

  output="$(
    HOME="$TMP_HOME" \
      AGENT_PLATFORM_HOME="$TMP_PLATFORM" \
      NPM_CONFIG_CACHE="$TMP_NPM_CACHE" \
      npm_config_cache="$TMP_NPM_CACHE" \
      npx --yes --package "$tarball_path" agent-control-plane setup \
        --non-interactive \
        --repo-root "${setup_repo}" \
        --repo-slug example/smoke-setup \
        --profile-id smoke-setup \
        --dry-run \
        --no-start-runtime \
        --skip-anchor-sync \
        --skip-workspace-sync
  )"

  grep -q '^SETUP_STATUS=dry-run$' <<<"${output}"
  grep -q '^SETUP_MODE=dry-run$' <<<"${output}"
  grep -q '^PROFILE_ID=smoke-setup$' <<<"${output}"
  grep -q "^REPO_ROOT=${setup_repo}\$" <<<"${output}"
  grep -q '^CORE_TOOLS_STATUS=' <<<"${output}"
)

run_sync_command_fixture() (
  set -euo pipefail
  local output=""

  output="$(
    HOME="$TMP_HOME" \
      AGENT_PLATFORM_HOME="$TMP_PLATFORM" \
      NPM_CONFIG_CACHE="$TMP_NPM_CACHE" \
      npm_config_cache="$TMP_NPM_CACHE" \
      npx --yes --package "$tarball_path" agent-control-plane sync
  )"

  grep -q '^SHARED_AGENT_HOME=' <<<"${output}"
)

run_cli_version_and_help_fixture() (
  set -euo pipefail
  local version_output=""
  local help_output=""
  local package_version=""

  version_output="$(
    HOME="$TMP_HOME" \
      AGENT_PLATFORM_HOME="$TMP_PLATFORM" \
      NPM_CONFIG_CACHE="$TMP_NPM_CACHE" \
      npm_config_cache="$TMP_NPM_CACHE" \
      npx --yes --package "$tarball_path" agent-control-plane version
  )"
  package_version="$(node -p "require('./package.json').version")"
  if [[ "${version_output}" != "${package_version}" ]]; then
    echo "version mismatch: expected ${package_version}, got ${version_output}" >&2
    return 1
  fi

  help_output="$(
    HOME="$TMP_HOME" \
      AGENT_PLATFORM_HOME="$TMP_PLATFORM" \
      NPM_CONFIG_CACHE="$TMP_NPM_CACHE" \
      npm_config_cache="$TMP_NPM_CACHE" \
      npx --yes --package "$tarball_path" agent-control-plane help
  )"
  grep -q '^Usage:' <<<"${help_output}"
  grep -q '^Commands:' <<<"${help_output}"
)

run_step "smoke" run_smoke_command_fixture
run_step "package-setup-dry-run" run_setup_dry_run_fixture
run_step "package-sync" run_sync_command_fixture
run_step "package-cli-version-and-help" run_cli_version_and_help_fixture

printf 'SMOKE_TEST_STATUS=ok\n'
