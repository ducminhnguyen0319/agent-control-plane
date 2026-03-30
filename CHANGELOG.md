# Changelog

All notable changes to `agent-control-plane` should be documented in this file.

The format is inspired by Keep a Changelog and uses a simple project-focused
layout for public releases.

## [Unreleased]

### Added

- release history tracking for public package and repository changes
- reusable release notes template for GitHub releases and publish announcements
- README badges for CI, npm, Node, license, and GitHub Sponsors
- reproducible dashboard demo media generation with screenshot and animated GIF
- public CI workflow for package and docs validation

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
