# Roadmap

`agent-control-plane` is being built as the operator layer for long-running
coding agents, not just a wrapper around one model or one CLI.

The roadmap below keeps that framing explicit: ACP should make multiple agent
backends feel manageable from one runtime, one dashboard, and one workflow
surface.

## Current Direction

The near-term product direction is:

- one control plane
- one per-repo profile model
- one dashboard
- multiple coding-worker backends behind a consistent runtime contract
- first-class platform support beyond the current macOS-heavy operator path

## Platform Support

ACP currently feels most complete on macOS because that is where launchd,
dashboard install flows, and most live demos have been validated.

The public roadmap should widen that base deliberately:

| Platform | Status | Why it matters next |
| --- | --- | --- |
| `macOS` | best supported today | Current reference platform for setup, launchd, dashboard, and local operator flows. |
| `Linux` | **in-progress** | systemd support added (v0.4.9+). ACP now validates runtime on Linux. Missing: full CI matrix, service validation. |
| `Windows (WSL2)` | exploratory next | A practical bridge for Windows users who still want Unix-like repos, containers, and worker CLIs. |
| `Native Windows` | longer-term | Needs explicit work around services, shell/process management, path handling, and backend compatibility. |

## Backend Support

ACP is intentionally explicit about backend maturity. Some adapters are ready
for real work today, while others are only scaffolded so the public package can
show where support is heading without pretending the integration is already
done.

| Backend | Status | Runtime Routing | Profile Scaffolding | Notes |
| --- | --- | --- | --- | --- |
| `codex` | production-ready | yes | yes | First-class worker path for Codex-backed runs. |
| `claude` | production-ready | yes | yes | First-class worker path for Claude-backed runs. Retry, timeout, and provider-quota handling. |
| `openclaw` | production-ready | yes | yes | First-class worker path with resident workflow support, stall detection, and host-side result inference. |
| `ollama` | **hardening** | yes | yes | Working adapter with Node.js agentic loop. **v0.4.9+: Added health-check + context detection.** Moved toward production-ready. |
| `pi` | experimental | yes | yes | Working adapter using the pi CLI. **Needs health-check + API key validation.** |
| `opencode` | experimental | yes | yes | Working adapter for Crush. **Needs health-check (verify `crush` binary).** |
| `kilo` | experimental | yes | yes | Working adapter for Kilo Code. **Needs health-check + JSON stream validation.** |
| `gemini-cli` | **integrated** | yes | yes | Google's official terminal agent (v0.39.1+). Full ACP adapter with health-check, API key validation, and streaming JSON output. |

### Production-Ready

These backends have full ACP workflow support, verified result contracts, and
consistent worker-status detection:

- `codex`
- `claude`
- `openclaw`

### Experimental

Working adapters with routing, profile scaffolding, and result contracts.
Useful for research, free-tier model testing, and local-model workflows:

- `ollama` — local models via Ollama API with tool-use support
- `pi` — OpenRouter-compatible models via the pi CLI
- `opencode` — Crush (charmbracelet/crush) with full tool execution
- `kilo` — Kilo Code (kilocode/cli) with JSON event stream output
- `gemini-cli` — Google's official terminal agent with streaming JSON output

### Planned Next

High-priority backend additions for the public package:

*(None currently — gemini-cli integrated in v0.5.0)*

## Adjacent Runtime and Model Integrations

Not every ecosystem target is a direct drop-in coding worker. Some are better
thought of as provider layers, local-model runtimes, or adjacent agent shells
that ACP should learn to work with over time.

| Target | Category | Status | Why it matters |
| --- | --- | --- | --- |
| `ollama` | local model runtime | **integrated** | Full ACP adapter with Node.js agentic loop, tool-use support, and git-state result inference. Setup wizard checks server readiness and available models. |
| `pi` | lightweight coding agent | **integrated** | Full ACP adapter with stall detection, exit markers, and proper result contracts. Setup wizard handles OpenRouter API key. |
| `nanoclaw` | containerized assistant runtime | not integrable | Standalone agent system (like ACP), not a CLI runtime. Useful reference for container isolation patterns. |
| `picoclaw` | lightweight assistant runtime (Go) | not integrable | Standalone agent system (Go-based, <10MB RAM). Runs on $10 hardware. Not a callable CLI backend. |

### Longer-Term Goal

ACP should eventually support a broader adapter model for:

- local coding-agent CLIs
- hosted coding-agent runtimes
- provider pools and failover chains across backends
- backend-specific capabilities without breaking the shared operator surface

## Product Roadmap

### 1. Multi-Backend Worker Layer

- keep strengthening `codex`, `claude`, and `openclaw`
- harden `ollama`, `pi`, `opencode`, and `kilo` experimental adapters toward production readiness
- standardize worker capability detection and backend health reporting
- improve fallback behavior when one backend is rate-limited or degraded

### 2. Platform Support

- keep macOS as the polished reference install path
- make Linux a first-class operator target with documented service/autostart patterns
- ~~support Windows users pragmatically through WSL2 before promising native parity~~ done: docs/WSL2_SETUP.md + README section, systemd scripts work in WSL2 with systemd enabled
- evaluate what native Windows runtime supervision should look like long-term

### 3. Public Package Experience

- ~~faster onboarding for first-time users~~ done: setup wizard now handles deps, auth, profile, runtime, dashboard, and starter issues in one pass
- stronger public docs, screenshots, badges, and demo flows
- ~~cleaner one-command setup paths for common repo profiles~~ done: `npx agent-control-plane@latest setup` is the single entry point
- release automation that keeps npm and GitHub release metadata aligned

### 4. Operator Experience

- ~~richer dashboard filtering and run-history views~~ done: filter UI added (search + status/result filters), run-history already existed
- ~~better visibility into cooldowns, retries, queue state, and failover events~~ done: time-remaining columns added to all relevant tables
- ~~clearer status reporting for recurring and scheduled workflows~~ done: time-remaining shows when next run/scheduled task is due
- ~~simpler tooling for troubleshooting real live profiles~~ done: troubleshooting panel with Run Doctor button added to dashboard

### 5. Team and Ecosystem Features

- ~~easier profile sharing across machines or team members~~ done: profile export + import fully implemented (API + dashboard buttons)
- ~~stronger contribution workflow and automation around CLA and docs policy~~ in progress: CLA.md added, test-cla-signed.sh + CI check added, docs links check added to CI
- ~~more reusable backend adapters so ACP is not locked to one agent ecosystem~~ done: all 6 adapters implement adapter-interface.sh (codex, claude, pi, opencode, kilo, openclaw), run-codex-task.sh refactored
- interoperability experiments with adjacent runtimes such as `nanoclaw` and `picoclaw`
- interoperability experiments with adjacent runtimes such as `nanoclaw` and `picoclaw`

## Notes

- items on this roadmap are directional, not guaranteed delivery promises
- backend names listed under `Planned Next` are targets for support, not claims
  of current integration beyond placeholder scaffolds where noted
- targets listed under `research next` or `exploratory` are ecosystem signals,
  not promises that ACP can operate them today
- the goal is to make ACP the dependable shell around many coding agents, not
  just the best wrapper for a single one
