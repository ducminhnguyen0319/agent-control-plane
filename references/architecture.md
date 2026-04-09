# Architecture Guide

This document explains how `agent-control-plane` is put together as an
operator-facing system, not just a collection of scripts.

ACP has five practical layers:

1. package entrypoint and staging
2. profile installation and publication
3. runtime supervision and heartbeat scheduling
4. worker execution and reconcile
5. dashboard and operator visibility

If you are reading the repo for the first time, start with the system overview
diagram below, then jump to the flow you care about most.

## System Overview

```mermaid
flowchart LR
  User[Operator] --> CLI["npm/bin/agent-control-plane.js"]

  CLI --> Init["project-init.sh"]
  CLI --> Sync["sync-shared-agent-home.sh"]
  CLI --> RuntimeCtl["project-runtimectl.sh"]
  CLI --> DashboardCmd["serve-dashboard.sh"]

  Init --> Profiles["Profile registry\n~/.agent-runtime/control-plane/profiles/<id>"]
  Sync --> RuntimeHome["Runtime home\n~/.agent-runtime/runtime-home"]

  RuntimeCtl --> Supervisor["project-runtime-supervisor.sh"]
  Supervisor --> Bootstrap["project-launchd-bootstrap.sh"]
  Bootstrap --> Heartbeat["heartbeat-safe-auto.sh"]
  Heartbeat --> Scheduler["agent-project-heartbeat-loop"]

  Scheduler --> IssueWorkers["start-issue-worker.sh"]
  Scheduler --> PRWorkers["start-pr-review-worker.sh\nstart-pr-fix-worker.sh\nstart-pr-merge-repair-worker.sh"]
  IssueWorkers --> Router["run-codex-task.sh"]
  PRWorkers --> Router

  Router --> Codex["agent-project-run-codex-session"]
  Router --> Claude["agent-project-run-claude-session"]
  Router --> OpenClaw["agent-project-run-openclaw-session"]
  Router --> Ollama["agent-project-run-ollama-session"]
  Router --> Pi["agent-project-run-pi-session"]
  Router --> OpenCode["agent-project-run-opencode-session"]
  Router --> Kilo["agent-project-run-kilo-session"]

  Codex --> Artifacts["run.env / runner.env /\nresult.env / verification.jsonl"]
  Claude --> Artifacts
  OpenClaw --> Artifacts
  Ollama --> Artifacts
  Pi --> Artifacts
  OpenCode --> Artifacts
  Kilo --> Artifacts

  Artifacts --> Reconcile["reconcile-issue-worker.sh\nreconcile-pr-worker.sh"]
  Reconcile --> GitHub["GitHub issues / PRs / labels / comments"]
  Reconcile --> History["runs/ + history/ + state/"]

  DashboardCmd --> Snapshot["dashboard_snapshot.py"]
  Snapshot --> Profiles
  Snapshot --> History
  Snapshot --> Browser["Local dashboard browser"]
```

The important architectural choice is that ACP separates:

- package distribution from runtime execution
- shared engine logic from per-profile config
- worker execution from reconcile and GitHub side effects
- operator visibility from the worker CLIs themselves

## Install and Publication Flow

This is the path from `npx agent-control-plane ...` to a usable runtime on disk.

```mermaid
sequenceDiagram
  participant User
  participant CLI as agent-control-plane.js
  participant Stage as staged shared-home
  participant Init as project-init.sh
  participant Scaffold as scaffold-profile.sh
  participant Smoke as profile-smoke.sh
  participant Adopt as profile-adopt.sh
  participant Sync as sync-shared-agent-home.sh

  User->>CLI: npx agent-control-plane init ...
  CLI->>Stage: copy packaged skill into temp shared-home
  CLI->>Init: forward command with staged env
  Init->>Scaffold: write control-plane.yaml + profile docs
  Init->>Smoke: validate profile contract
  Init->>Adopt: create runtime roots / sync anchor repo / workspace
  Init->>Sync: publish shared runtime into ~/.agent-runtime/runtime-home
```

Why this split exists:

- the npm package is treated as a distribution artifact
- the real runtime is copied into `~/.agent-runtime/runtime-home`
- installed profiles live outside the package in
  `~/.agent-runtime/control-plane/profiles/<id>`
- upgrades are therefore explicit and repeatable instead of depending on a temp
  `npx` cache directory

## Runtime Scheduler Loop

This is the heartbeat path ACP follows after `runtime start`.

```mermaid
flowchart TD
  Start["runtime start"] --> RuntimeCtl["project-runtimectl.sh"]
  RuntimeCtl --> Supervisor["project-runtime-supervisor.sh"]
  Supervisor --> Bootstrap["project-launchd-bootstrap.sh"]
  Bootstrap --> SyncCheck["sync runtime copy if needed"]
  SyncCheck --> Heartbeat["heartbeat-safe-auto.sh"]
  Heartbeat --> Preflight["locks / quota preflight /\nretained-worktree audit"]
  Preflight --> SharedLoop["agent-project-heartbeat-loop"]

  SharedLoop --> ReconcileCompleted["reconcile completed sessions"]
  SharedLoop --> Capacity["compute capacity / cooldown / pending launches"]
  SharedLoop --> Workflows["select workflow lane from issue + PR state"]

  Workflows --> IssueImplementation["issue implementation"]
  Workflows --> IssueScheduled["scheduled issue checks"]
  Workflows --> IssueRecovery["blocked recovery"]
  Workflows --> PRReview["PR review"]
  Workflows --> PRFix["PR fix"]
  Workflows --> PRMergeRepair["merge repair"]
```

Key detail: the shared scheduler owns the control logic around workers:

- concurrency and heavy-worker limits
- cooldown and retry gating
- resident recurring and scheduled issue lanes
- launch ordering
- summary output and queue visibility

That is why workers do not need to be "smart" about the entire system. The
workflow around them carries a lot of the operational burden.

## Worker Session Lifecycle

This is the path from one chosen issue or PR to a reconciled outcome.

```mermaid
flowchart LR
  Pick["heartbeat selects issue or PR"] --> Launch["start-issue-worker.sh\nor start-pr-*.sh"]
  Launch --> Worktree["open or reuse managed worktree"]
  Worktree --> Prompt["render prompt + context files"]
  Prompt --> Route["run-codex-task.sh"]

  Route --> Backend["Codex / Claude / OpenClaw adapter"]
  Backend --> Session["backend session wrapper"]
  Session --> Output["result.env / comments /\nverification.jsonl / runner.env"]

  Output --> Reconcile["agent-project-reconcile-issue-session\nor agent-project-reconcile-pr-session"]
  Reconcile --> Labels["update labels / retry state /\nresident metadata / cooldown"]
  Reconcile --> Publish["comment on issue, open PR,\nor leave blocked report"]
  Reconcile --> Archive["archive run into history root"]
```

The contract here is deliberate:

- worker backends focus on producing work and result artifacts
- reconcile scripts own the final interpretation and GitHub-facing outcome
- resident metadata and history are updated by the host workflow, not by the
  worker trying to infer the entire system state

## Dashboard Snapshot Pipeline

The dashboard is a read-only window into ACP state. It does not own scheduling.

```mermaid
flowchart LR
  Browser["browser"] --> Server["tools/dashboard/server.py"]
  Server --> API["GET /api/snapshot.json"]
  API --> Snapshot["dashboard_snapshot.py"]

  Snapshot --> Registry["profile registry"]
  Snapshot --> Config["render-flow-config.sh"]
  Snapshot --> WorkerStatus["agent-project-worker-status"]
  Snapshot --> Runs["runs/ history/ state/"]

  Registry --> JSON["snapshot payload"]
  Config --> JSON
  WorkerStatus --> JSON
  Runs --> JSON

  JSON --> UI["dashboard app.js + index.html"]
```

This means the dashboard reflects the current state of:

- installed profiles
- live and recent runs
- resident controller metadata
- provider cooldowns
- scheduled issue state
- runtime process status

without introducing a second control path that could drift away from the real
scheduler state.

## Reading Order

If you want the shortest path through the architecture:

1. [System Overview](#system-overview)
2. [Runtime Scheduler Loop](#runtime-scheduler-loop)
3. [Worker Session Lifecycle](#worker-session-lifecycle)
4. [Dashboard Snapshot Pipeline](#dashboard-snapshot-pipeline)

If you are changing packaging or onboarding, also read
[Install and Publication Flow](#install-and-publication-flow).
