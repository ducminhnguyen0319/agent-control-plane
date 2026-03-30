# Changelog

All notable changes to `agent-control-plane` should be documented in this file.

The format is inspired by Keep a Changelog and uses a simple project-focused
layout for public releases.

## [Unreleased]

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
