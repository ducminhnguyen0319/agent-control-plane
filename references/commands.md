# Command Map

Run commands from the current isolated checkout for the task.

Profile-specific repo roots and repo-local dev/test commands belong in
`~/.agent-runtime/control-plane/profiles/<id>/README.md`. Resolve the active
profile first, then use the selected profile's notes for product-repo commands.

## Profile Resolution

```bash
bash tools/bin/workflow-catalog.sh profiles
tools/bin/workflow-catalog.sh context
bash tools/bin/profile-activate.sh --profile-id <id>
ACP_PROJECT_ID=<id> bash tools/bin/render-flow-config.sh
```

Use `render-flow-config.sh` when you need the effective repo root, worktree
root, runtime root, worker backend, or profile-specific script bindings.
When multiple available profiles exist, set `ACP_PROJECT_ID=<id>` first or use
`profile-activate.sh --profile-id <id>` before running manual operator
commands.

## Dependency bootstrap

Run dependency bootstrap only from the clean automation baseline for the
selected profile when you explicitly need to refresh shared dependencies. Do not
repair shared `node_modules` from inside a worker worktree.

For control-plane changes in this repo, prefer focused shell tests over broad
bootstrap unless the task actually changes dependency behavior.

## Control-Plane Verification

```bash
bash tools/bin/check-skill-contracts.sh
bash tools/bin/flow-runtime-doctor.sh
bash tools/bin/profile-smoke.sh
bash tools/bin/test-smoke.sh
bash tools/tests/test-project-init.sh
bash tools/tests/test-project-init-force-and-skip-sync.sh
bash tools/tests/test-project-remove.sh
bash tools/tests/test-project-runtimectl.sh
bash tools/tests/test-project-runtimectl-missing-profile.sh
bash tools/tests/test-project-runtimectl-stop-cancels-pending-kick.sh
bash tools/tests/test-project-runtimectl-start-falls-back-to-bootstrap.sh
bash tools/tests/test-project-runtimectl-status-supervisor-running.sh
bash tools/tests/test-project-launchd-bootstrap.sh
bash tools/tests/test-install-project-launchd.sh
bash tools/tests/test-uninstall-project-launchd.sh
bash tools/tests/test-project-runtimectl-launchd.sh
bash tools/tests/test-dashboard-launchd-bootstrap.sh
bash tools/tests/test-install-dashboard-launchd.sh
bash tools/tests/test-render-dashboard-snapshot.sh
bash tools/tests/test-serve-dashboard.sh
bash tools/tests/test-control-plane-dashboard-runtime-smoke.sh
bash tools/tests/test-workflow-catalog.sh
bash tools/tests/test-render-flow-config.sh
```

Add or run targeted tests in `tools/tests/` for the changed surface.

## Flow maintenance

```bash
tools/bin/flow-runtime-doctor.sh
tools/bin/workflow-catalog.sh list
tools/bin/workflow-catalog.sh show pr-review
tools/bin/workflow-catalog.sh profiles
tools/bin/workflow-catalog.sh context
tools/bin/profile-activate.sh --profile-id <id>
tools/bin/project-init.sh --profile-id <id> --repo-slug <owner/repo>
tools/bin/render-flow-config.sh
tools/bin/scaffold-profile.sh --profile-id <id> --repo-slug <owner/repo>
tools/bin/profile-smoke.sh
tools/bin/test-smoke.sh
tools/bin/profile-adopt.sh --profile-id <id>
tools/bin/project-runtimectl.sh status --profile-id <id>
tools/bin/project-runtimectl.sh sync --profile-id <id>
tools/bin/project-runtimectl.sh stop --profile-id <id>
tools/bin/project-runtimectl.sh start --profile-id <id>
tools/bin/project-runtimectl.sh restart --profile-id <id>
tools/bin/install-project-launchd.sh --profile-id <id>
tools/bin/uninstall-project-launchd.sh --profile-id <id>
tools/bin/project-remove.sh --profile-id <id>
tools/bin/project-remove.sh --profile-id <id> --purge-paths
tools/bin/sync-shared-agent-home.sh
python3 tools/dashboard/dashboard_snapshot.py --pretty
bash tools/bin/serve-dashboard.sh --host 127.0.0.1 --port 8765
bash tools/bin/install-dashboard-launchd.sh --host 127.0.0.1 --port 8765
```

Installed profile prompts should live under
`~/.agent-runtime/control-plane/profiles/<id>/templates/`; generic fallback
prompts live under `tools/templates/`.

## Dashboard

```bash
python3 tools/dashboard/dashboard_snapshot.py --pretty
bash tools/bin/serve-dashboard.sh --host 127.0.0.1 --port 8765
bash tools/bin/install-dashboard-launchd.sh --host 127.0.0.1 --port 8765
```

Use the snapshot command for CLI/debug output and the HTTP server for the live
dashboard at `http://127.0.0.1:8765`. Use the LaunchAgent installer when you
want the dashboard to come back automatically after macOS restart/login.

## Project Autostart

```bash
# macOS (launchd)
bash tools/bin/install-project-launchd.sh --profile-id <id>
bash tools/bin/uninstall-project-launchd.sh --profile-id <id>

# Linux (systemd)
bash tools/bin/install-project-systemd.sh --profile-id <id>
bash tools/bin/uninstall-project-systemd.sh --profile-id <id>
```

Use the project installer when one profile should come back automatically after
macOS restart/login or Linux logout/login. `project-runtimectl.sh start|stop|status` will detect launchd or systemd automatically once installed.

## Repo-Specific Commands

After choosing a profile, read `~/.agent-runtime/control-plane/profiles/<id>/README.md` for:

- clean automation baseline and retained checkout roots
- repo-local startup docs such as `AGENTS.md` and OpenSpec paths
- app/package-specific dev commands
- isolated smoke and release-rehearsal commands
- project-specific operator runbooks
