# Task

Run the scheduled verification task for issue #{ISSUE_ID} in `{REPO_SLUG}`.

# Issue Context

- Title: {ISSUE_TITLE}
- URL: {ISSUE_URL}

{ISSUE_BODY}
{ISSUE_BLOCKER_CONTEXT}

# Scheduled Task Rules

- This is a scheduled check/report cycle, not an implementation cycle.
- Do not modify code, do not create a commit, do not open a PR, and do not change production state.
- Use the issue body as the source of truth for what to verify and which commands or checks to run.
- If the issue body is too vague to run a safe scheduled check, treat that as an alert and report it instead of inventing scope.
- Work only inside the dedicated worktree for this issue.
- The dedicated worktree may use an agent branch name. That is acceptable for scheduled checks.
- The host prepared this run against baseline commit `{ISSUE_BASELINE_HEAD_SHA}`. Treat that fixed SHA as the source of truth for the run.
- Before commands start, confirm the dedicated worktree `HEAD` exactly matches `{ISSUE_BASELINE_HEAD_SHA}`.
- The host may prepare linked dependencies or generated artifacts that are expected for this scheduled run.
- Only alert if the checked-out commit is wrong or if there are unexpected tracked or untracked product changes beyond those expected worker artifacts.

# Verification

- Run the narrowest commands or health checks that satisfy the scheduled task.
- Prefer deterministic read-only commands.
- For prod or system-health checks, do not perform destructive operations.
- Retry transient network-dependent failures before declaring an alert unless the issue defines a stricter rule.
- Capture concrete pass/fail evidence: commands run, key output, and the main signal you relied on.

# Result Contract

- Write `$ACP_RUN_DIR/issue-comment.md` with a short Markdown report containing:
  - `## Scheduled check result`
  - `Outcome: pass` or `Outcome: alert`
  - `Commands run`
  - `Evidence`
  - `Next due behavior remains host-controlled by schedule`
- If everything is healthy, write `$ACP_RESULT_FILE` exactly like this:
  ```bash
  cat > "$ACP_RESULT_FILE" <<'EOF'
  OUTCOME=reported
  ACTION=host-comment-scheduled-report
  ISSUE_ID={ISSUE_ID}
  EOF
  ```
- If any check fails, the schedule definition is ambiguous, credentials are missing, or you detect a regression, still report instead of blocking the lane. Write `$ACP_RESULT_FILE` exactly like this:
  ```bash
  cat > "$ACP_RESULT_FILE" <<'EOF'
  OUTCOME=reported
  ACTION=host-comment-scheduled-alert
  ISSUE_ID={ISSUE_ID}
  EOF
  ```

# Stop

- Stop after writing the Markdown report and the result file.
- The host reconciler will post the report comment, keep the issue open, clean the session, and let the next run be driven by the stored schedule.
