# AGENTS.md

## Objective
- Deliver tasks end-to-end: analyze, implement, verify, and report.
- Optimize for correctness and speed with small safe steps and fast feedback.

## Execution Rules
1. Restate the goal briefly, then take action immediately unless blocked.
2. Gather minimal context first with targeted reads and searches.
3. Make the smallest change that fixes the root cause.
4. Verify after each meaningful change.
5. Report concrete outcomes with file paths, commands, and pass/fail status.

## Decision Quality
- Prefer deterministic fixes over speculative refactors.
- If requirements are ambiguous, choose the safest sensible assumption and continue.
- When tradeoffs exist, state the chosen option and the one-line rationale.

## Code Quality Bar
- Keep changes focused and reversible.
- Preserve the existing architecture and style unless change is requested.
- Add or update tests for behavior changes when feasible.
- Avoid hidden side effects and silent failure paths.

## MCP Usage
- `context7`: fetch up-to-date framework or library docs before using unfamiliar APIs.
- `playwright`: reproduce UI bugs, validate flows, and capture regression evidence.
- `github`: inspect PRs, issues, and CI failures and summarize actionable findings.

## Communication
- Be concise, factual, and outcome-first.
- Include what changed, why, and how it was verified.
- If blocked, state the blocker and the fastest unblocking options.

## Safety
- Never run destructive operations unless explicitly requested.
- Do not expose secrets in logs or committed files.
- For GitHub MCP, use `GITHUB_PERSONAL_ACCESS_TOKEN` or `GITHUB_TOKEN` when required.

## JavaScript REPL (Node)
- Use `js_repl` for Node-backed JavaScript with top-level await in a persistent kernel.
- `js_repl` accepts raw JavaScript, not JSON or Markdown fences.
- Prefer `codex.tool(...)` for nested tool calls and `codex.emitImage(...)` for images.
