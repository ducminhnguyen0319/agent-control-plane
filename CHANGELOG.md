# Changelog

All notable changes to `agent-control-plane` should be documented in this file.

The format is inspired by Keep a Changelog and uses a simple project-focused
layout for public releases.

## [0.2.0] - 2026-04-10

### Added

- GitHub Actions trusted publishing workflow for tag-driven npm releases without
  local OTP prompts
- stall detection watchdog for the Pi backend when neither `timeout` nor
  `gtimeout` is available (background fallback path)
- exit marker (`__CODEX_EXIT__`) for Pi and Ollama session runners so
  worker-status can detect completion via the primary log-based path
- setup wizard offers to create recurring starter issues (`agent-keep-open`)
  so ACP starts working on the repo immediately after installation; five
  built-in templates: code quality, test coverage, documentation,
  dependency audit, and refactoring sweeps
- setup wizard offers to launch the monitoring dashboard in background as
  part of the guided flow (`--start-dashboard` / `--dashboard-port`)
- setup wizard checks Ollama readiness (server running, models available)
  when the `ollama` backend is selected
- Pi backend now prompts for `OPENROUTER_API_KEY` during interactive setup,
  same as the existing openclaw prompt
- post-setup summary now shows created starter issues, dashboard URL, and
  a "Getting started" section with clear first-use instructions
- opencode (Crush) adapter: full session runner using `crush run` with
  non-interactive execution, git-state result inference, timeout handling,
  exit marker, and proper RUNNER_STATE
- kilo adapter: full session runner using `kilo run --auto --format json`
  with structured JSON event output, git-state result inference, timeout
  handling, exit marker, and proper RUNNER_STATE

### Fixed

- unified `RUNNER_STATE` values across all backends: Claude wrote `completed`
  instead of `succeeded`, Ollama wrote `completed`, and Pi wrote
  `success`/`failure` — worker-status only recognised `succeeded`/`failed`, so
  non-Codex workers relied on the weaker result.env fallback for status
  detection
- broadened the worker-status exit-marker regex from the hard-coded
  `__CODEX_EXIT__:` to `__\w+_EXIT__:` so Claude's `__CLAUDE_EXIT__:` (and
  any future backend marker) is detected without a caller-side override
- Pi and Ollama result contracts now write a valid `OUTCOME`/`ACTION` envelope
  instead of the bare `STATUS=success` that reconcile could never match,
  eliminating perpetual `invalid-result-contract` failures for those backends
- Ollama Node.js agent no longer writes a blanket `OUTCOME=blocked` on
  success; the host bash wrapper now infers the outcome from git state so
  product changes can reach the publish path
- OpenClaw `infer_result_from_output` no longer overrides an agent-written
  `OUTCOME=implemented` to blocked when `verification.jsonl` is missing —
  the host reconcile's verification recovery now gets a chance to run first
- OpenClaw git-change detection (`git log`) now filters `.md`,
  `.openclaw-artifacts`, and `.agent-session.env` so doc-only commits no
  longer trigger a false "product changes without verification" block
- OpenClaw blocked-keyword grep narrowed from broad terms (`blocked`,
  `cannot proceed`) to explicit agent decisions (`^OUTCOME=blocked`,
  `^I am blocked`) to avoid false positives from prompt context echoed in
  the log
- reconcile FAILED path for `provider-quota-limit` no longer preserves a
  stale `OUTCOME=implemented` from a prior cycle's result.env, fixing
  resident metadata that showed a misleading last-outcome after quota
  failures
- heartbeat snapshot cache now uses disk-only caching (removed ineffective
  in-memory variables that were always lost in subshell callers) and adds
  disk cache for `heartbeat_open_agent_pr_issue_ids`
- heartbeat loop cleanup now calls `heartbeat_invalidate_snapshot_cache` on
  exit, preventing `/tmp` accumulation of PID-scoped cache directories
- reconcile watch-mode detection regex extended to catch `vitest watch`
  (without `--` prefix) so `npm test` is not used as a fallback for
  watch-mode test scripts
- heartbeat catch-up passes (merged-PR, linked-issue, scheduled-retry) are
  now throttled to run at most once every 5 minutes instead of every
  heartbeat cycle, reducing GitHub API quota burn
- fixed 12 pre-existing test failures caused by missing `gh api rate_limit`
  stubs and outdated test expectations for openclaw session IDs,
  failure-reason inference, and reconcile summary clearing

### Changed

- maintainer release docs now point to trusted publishing through
  `.github/workflows/publish.yml` instead of local `npm publish`
- setup wizard, `init`, and `scaffold-profile` now accept `ollama` and `pi`
  as `--coding-worker` values alongside the existing `codex`, `claude`, and
  `openclaw`
- scaffolded profile YAML now includes default `ollama` and `pi`
  configuration sections

## [0.1.8] - 2026-03-31

### Fixed

- forced detached worker launches to start from a stable working directory, so resident issue loops no longer inherit a deleted worktree cwd and break `pnpm`/Node bootstrap with `uv_cwd`
- added regression coverage for detached launches started from a stale parent cwd
- made Claude session runners stream turn output in real time and reap the Claude child process when the parent session is terminated, so resident Claude workers no longer leave orphaned long-running processes behind as easily
- switched headless Claude prompting to stdin-backed transport with isolated hooks/MCP settings, so resident Claude workers no longer hang before doing real work
- classify Claude provider quota failures from debug logs and preserve the worker's blocked result contract instead of collapsing them into generic exit failures
- ensure issue and PR reconcile hooks pass the resolved profile id into `kick-scheduler.sh`, so post-reconcile scheduling still works when multiple profiles are installed
- surface provider quota blocker comments on GitHub issues during failed reconcile paths, so recurring Claude lanes fail visibly instead of going silent

## [0.1.7] - 2026-03-30

### Fixed

- restored the packaged `references/` docs needed by `smoke`, so `npx agent-control-plane@latest smoke` works from the public npm tarball
- added package-level regression coverage that runs the published smoke command against the built tarball

## [0.1.6] - 2026-03-30

### Fixed

- ensure `setup` materializes the configured `agent_repo_root` even when anchor sync is skipped, so custom path installs do not leave the anchor repo path missing

## [0.1.5] - 2026-03-30

### Fixed

- restored an explicit published `bin` entry so `npx agent-control-plane@latest ...` works directly from the npm registry
- moved the public executable wrapper to `bin/agent-control-plane` and added tarball-level regression coverage for the packaged executable metadata

## [0.1.4] - 2026-03-30

### Fixed

- removed maintainer-only render scripts from the public npm tarball
- removed the vendored `codex-quota` README from the public npm tarball to keep shipped package contents focused on runtime code
- added a tarball-surface regression so CI now checks the published package contents directly

## [0.1.3] - 2026-03-30

### Fixed

- removed `tools/tests` from the public npm tarball so maintainer-only regression fixtures are no longer shipped to end users
- reduced the public package surface without changing the runtime setup or worker behavior exposed by the CLI

## [0.1.2] - 2026-03-30

### Fixed

- removed browser-cookie and session-key fallback logic from the bundled Claude quota path
- restricted bundled Claude quota support to OAuth-backed credentials only
- added regression coverage to keep the public npm bundle free of Claude browser-cookie harvesting logic

## [0.1.1] - 2026-03-30

### Fixed

- corrected public GitHub repository links in README badges and package metadata
- published npm metadata that now points to the public `ducminhnguyen0319/agent-control-plane` repository
- removed the last legacy internal username fixture from the repo snapshot

## [0.1.0] - 2026-03-27

### Added

- npm-distributed `agent-control-plane` CLI with `sync`, `init`, `doctor`,
  `dashboard`, `runtime`, `profile-smoke`, and `smoke` commands
- packaged runtime bootstrap flow for installing ACP into
  `~/.agent-runtime/runtime-home`
- public package metadata including homepage, bugs URL, repository, funding,
  and `MIT` license
- contributor governance docs: `CONTRIBUTING.md`, `CLA.md`,
  `CODE_OF_CONDUCT.md`, and `SECURITY.md`
- release support docs including maintainer release checklist and release notes
  template
