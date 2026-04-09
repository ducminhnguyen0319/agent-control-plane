# Agent Control Plane Map

This repository is the shared `agent-control-plane` package. It provides a
generic engine that can host multiple installed profiles, each with its own repo
roots, labels, worker preferences, prompts, and project-specific guardrails.

## What Lives Here

- `SKILL.md`
  Canonical operating manual for the shared control plane.
- `~/.agent-runtime/control-plane/profiles/<id>/control-plane.yaml`
  Canonical installed project profile for repo paths, queue labels, limits,
  and script bindings.
- `~/.agent-runtime/control-plane/profiles/<id>/README.md`
  Repo-specific operator notes, startup docs, and command references for the
  selected profile.
- `~/.agent-runtime/control-plane/profiles/<id>/templates/`
  Optional installed profile-specific prompt overrides.
- `assets/workflow-catalog.json`
  Declarative catalog of the workflow lanes this control plane exposes.
- `bin/`
  Queue, label, and risk logic shared by installed profiles.
- `hooks/`
  Heartbeat and reconcile hooks shared by installed profiles.
- `tools/bin/flow-runtime-doctor.sh`
  Reports whether the published source copy and runtime-home copy are in sync.
- `tools/bin/workflow-catalog.sh`
  Lists workflows, shows workflow details, or prints available profile ids.
- `tools/bin/render-flow-config.sh`
  Prints the effective operator/runtime config after environment overrides.
- `tools/bin/run-codex-task.sh`
  Routes the shared worker contract into the backend-specific session wrapper.
- `tools/bin/agent-project-run-codex-session`
  Launches Codex-backed worker sessions.
- `tools/bin/agent-project-run-claude-session`
  Launches Claude-backed worker sessions.
- `tools/bin/agent-project-run-openclaw-session`
  Launches OpenClaw-backed worker sessions.
- `tools/bin/agent-project-run-ollama-session`
  Launches Ollama-backed worker sessions with a Node.js agentic loop.
- `tools/bin/agent-project-run-pi-session`
  Launches Pi-backed worker sessions in `--print --no-session` mode.
- `tools/bin/agent-project-run-opencode-session`
  Launches Crush (formerly OpenCode) worker sessions via `crush run`.
- `tools/bin/agent-project-run-kilo-session`
  Launches Kilo Code worker sessions via `kilo run --auto --format json`.
- `tools/bin/project-init.sh`
  Runs scaffold + smoke + adopt + runtime sync for one installed profile.
- `tools/bin/scaffold-profile.sh`
  Scaffolds a new installed profile, profile notes, and prompt templates in the
  local profile registry.
- `tools/bin/project-runtimectl.sh`
  Provides `status`, `start`, `stop`, and `restart` for one installed profile.
- `tools/bin/project-launchd-bootstrap.sh`
  Syncs the runtime copy and runs one profile-scoped heartbeat pass in a
  launchd-safe foreground process for the runtime supervisor.
- `tools/bin/install-project-launchd.sh`
  Installs a per-user LaunchAgent for one installed profile so its runtime can
  come back automatically after reboot/login.
- `tools/bin/uninstall-project-launchd.sh`
  Removes the per-project LaunchAgent wrapper and plist for one installed
  profile.
- `tools/bin/project-remove.sh`
  Removes one installed profile plus ACP-owned runtime state, with optional
  purge of ACP-managed repo/worktree/workspace paths.
- `tools/bin/profile-smoke.sh`
  Validates available profiles and catches session/branch prefix collisions
  before scheduler use.
- `tools/bin/test-smoke.sh`
  Runs the main shared-package smoke gates in one operator-facing command.
- `tools/dashboard/dashboard_snapshot.py`
  Emits a JSON snapshot of active runs, resident controllers, cooldown state,
  queue depth, and scheduled issues across installed profiles.
- `tools/bin/serve-dashboard.sh`
  Serves the live worker dashboard and `/api/snapshot.json` endpoint for local
  browser-based monitoring.
- `tools/bin/dashboard-launchd-bootstrap.sh`
  Syncs the runtime copy and launches the dashboard server in a launchd-safe
  foreground process.
- `tools/bin/install-dashboard-launchd.sh`
  Installs and bootstraps a per-user LaunchAgent so the dashboard returns after
  reboot/login.
- `tools/bin/profile-adopt.sh`
  Creates runtime roots, installs the selected profile into the local profile
  registry when needed, and syncs the anchor repo plus VS Code workspace for
  live scheduler adoption.
- `references/`
  Control-plane docs, operator commands, and repository maps.

## What Does Not Live Here

- Repo-specific product code.
- Local scheduler bootstrap and operator docs that belong to a particular
  workstation. Those now live under:
  `~/.agent-runtime/control-plane/workspace`

## Vendored Runtime

- Runtime engines are resolved from the current skill root first, then the
  shared/runtime canonical copies when present, while active project profiles
  are resolved from `~/.agent-runtime/control-plane/profiles/`.
- Project-specific instructions should be loaded from the active profile's
  `README.md` and templates instead of being hardcoded into the shared engine.

## Published Artifacts

- Source canonical package copy:
  `$SHARED_AGENT_HOME/skills/openclaw/agent-control-plane`
- Runtime canonical package copy:
  `~/.agent-runtime/runtime-home/skills/openclaw/agent-control-plane`

Published artifacts are rebuilt by `tools/bin/sync-shared-agent-home.sh` as
concrete copied files, not symlink aliases. Canonical profile configs now live
outside the repo in `~/.agent-runtime/control-plane/profiles/<id>/control-plane.yaml`.

## Operational Rule

When updating the control plane:

1. Change the generic engine in this repo or the selected installed profile in the external registry.
2. Keep workstation wrappers thin.
3. Repair shared/runtime published copies with `tools/bin/sync-shared-agent-home.sh`.
4. Prefer explicit profile docs and copied artifacts over hidden defaults and
   symlink aliases.
