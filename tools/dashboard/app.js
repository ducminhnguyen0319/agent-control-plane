const refreshButton = document.querySelector("#refresh-button");
const generatedAtNode = document.querySelector("#generated-at");
const overviewNode = document.querySelector("#overview");
const profilesNode = document.querySelector("#profiles");

function relativeTime(input) {
  if (!input) return "n/a";
  const value = new Date(input);
  if (Number.isNaN(value.getTime())) return input;
  const seconds = Math.round((Date.now() - value.getTime()) / 1000);
  const absolute = Math.abs(seconds);
  const parts = [
    [86400, "d"],
    [3600, "h"],
    [60, "m"],
  ];
  for (const [unitSeconds, label] of parts) {
    if (absolute >= unitSeconds) {
      const amount = Math.round(absolute / unitSeconds);
      return seconds >= 0 ? `${amount}${label} ago` : `in ${amount}${label}`;
    }
  }
  return seconds >= 0 ? `${absolute}s ago` : `in ${absolute}s`;
}

function statusClass(status) {
  if (!status) return "";
  return status.replace(/[^a-zA-Z0-9_-]/g, "-");
}

function renderLifecycle(row) {
  const note = row.result_only_completion === "yes" ? `<div class="muted">Recovered from result file</div>` : "";
  return `<span class="status-pill ${statusClass(row.lifecycle_status || row.status)}">${row.lifecycle_status || row.status || "UNKNOWN"}</span>${note}`;
}

function renderResult(row) {
  const primary = row.result_label || row.outcome || row.failure_reason || "n/a";
  const secondary = [];
  if (row.outcome && primary !== row.outcome) secondary.push(row.outcome);
  if (row.action) secondary.push(row.action);
  return `<span class="status-pill ${statusClass(row.result_kind || "unknown")}">${primary}</span>${
    secondary.length ? `<div class="muted">${secondary.join(" · ")}</div>` : ""
  }`;
}

function renderControllerState(row) {
  const state = row.state || "n/a";
  const stale = row.controller_stale === true || (state !== "stopped" && row.controller_live === false);
  const label = stale ? `${state} (stale)` : state;
  return `<span class="status-pill ${statusClass(stale ? "stale" : state)}">${label}</span>`;
}

function renderOverview(snapshot) {
  const totals = snapshot.profiles.reduce(
    (acc, profile) => {
      acc.activeRuns += profile.counts.active_runs;
      acc.runningRuns += profile.counts.running_runs;
      acc.implementedRuns += profile.counts.implemented_runs;
      acc.reportedRuns += profile.counts.reported_runs;
      acc.blockedRuns += profile.counts.blocked_runs;
      acc.controllers += profile.counts.live_resident_controllers;
      acc.cooldowns += profile.counts.provider_cooldowns;
      acc.queue += profile.counts.queued_issues;
      return acc;
    },
    { activeRuns: 0, runningRuns: 0, implementedRuns: 0, reportedRuns: 0, blockedRuns: 0, controllers: 0, cooldowns: 0, queue: 0 },
  );

  overviewNode.innerHTML = [
    ["Profiles", snapshot.profile_count],
    ["Run sessions", totals.activeRuns],
    ["Running", totals.runningRuns],
    ["Implemented", totals.implementedRuns],
    ["Reported", totals.reportedRuns],
    ["Blocked", totals.blockedRuns],
    ["Live Controllers", totals.controllers],
    ["Provider Cooldowns", totals.cooldowns],
    ["Queued Issues", totals.queue],
  ]
    .map(
      ([label, value]) => `
        <article class="card">
          <div class="stat-label">${label}</div>
          <div class="stat-value">${value}</div>
        </article>
      `,
    )
    .join("");
}

function renderTable(columns, rows, emptyMessage = "No data right now.") {
  if (!rows.length) {
    return `<div class="empty-state">${emptyMessage}</div>`;
  }
  const headers = columns.map((column) => `<th>${column.label}</th>`).join("");
  const body = rows
    .map((row) => {
      const cells = columns
        .map((column) => `<td>${column.render ? column.render(row) : row[column.key] ?? ""}</td>`)
        .join("");
      return `<tr>${cells}</tr>`;
    })
    .join("");
  return `<div class="table-wrap"><table><thead><tr>${headers}</tr></thead><tbody>${body}</tbody></table></div>`;
}

function renderProfile(profile) {
  const providerBadges = [
    profile.coding_worker ? `<span class="badge good">${profile.coding_worker}</span>` : "",
    profile.provider_pool.backend
      ? `<span class="badge">${profile.provider_pool.backend}: ${profile.provider_pool.model || "n/a"}</span>`
      : "",
    profile.provider_pool.name ? `<span class="badge">${profile.provider_pool.name}</span>` : "",
    profile.provider_pool.last_reason ? `<span class="badge warn">${profile.provider_pool.last_reason}</span>` : "",
  ]
    .filter(Boolean)
    .join("");

  const summaryCards = [
    ["Run sessions", profile.counts.active_runs],
    ["Running", profile.counts.running_runs],
    ["Implemented", profile.counts.implemented_runs],
    ["Reported", profile.counts.reported_runs],
    ["Blocked", profile.counts.blocked_runs],
    ["Live controllers", profile.counts.live_resident_controllers],
    ["Stale controllers", profile.counts.stale_resident_controllers],
    ["Provider cooldowns", profile.counts.provider_cooldowns],
    ["Issue retries", profile.counts.active_retries],
    ["Queued issues", profile.counts.queued_issues],
    ["Scheduled", profile.counts.scheduled_issues],
  ]
    .map(
      ([label, value]) => `
        <article class="card">
          <div class="stat-label">${label}</div>
          <div class="stat-value">${value}</div>
        </article>
      `,
    )
    .join("");

  const runsTable = renderTable(
    [
      { label: "Session", render: (row) => `<div class="mono">${row.session}</div>` },
      { label: "Task", render: (row) => `${row.task_kind || "n/a"} ${row.task_id || ""}`.trim() },
      { label: "Lifecycle", render: renderLifecycle },
      { label: "Worker", key: "coding_worker" },
      { label: "Provider", render: (row) => row.provider_model || "n/a" },
      { label: "Result", render: renderResult },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${row.updated_at}</div>` : "n/a" },
    ],
    profile.runs,
    "No active run directories for this profile.",
  );

  const controllerTable = renderTable(
    [
      { label: "Issue", key: "issue_id" },
      { label: "State", render: renderControllerState },
      { label: "Reason", render: (row) => row.reason || "n/a" },
      { label: "Provider", render: (row) => `${row.provider_backend || "n/a"} ${row.provider_model || ""}`.trim() },
      { label: "Failover", render: (row) => `${row.provider_failover_count} failovers / ${row.provider_switch_count} switches` },
      { label: "Wait", render: (row) => `${row.provider_wait_count} waits / ${row.provider_wait_total_seconds}s` },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${row.updated_at}</div>` : "n/a" },
    ],
    profile.resident_controllers,
    "No resident controllers recorded for this profile.",
  );

  const retryTable = renderTable(
    [
      { label: "Issue", key: "issue_id" },
      { label: "Status", render: (row) => `<span class="status-pill ${row.ready ? "" : "waiting-provider"}">${row.ready ? "ready" : "retrying"}</span>` },
      { label: "Reason", render: (row) => row.last_reason || "n/a" },
      { label: "Attempts", key: "attempts" },
      { label: "Next attempt", render: (row) => row.next_attempt_at ? `${relativeTime(row.next_attempt_at)}<div class="muted">${row.next_attempt_at}</div>` : "n/a" },
    ],
    profile.issue_retries || [],
    "No issue retries recorded.",
  );

  const workerTable = renderTable(
    [
      { label: "Key", render: (row) => `<div class="mono">${row.key}</div>` },
      { label: "Scope", key: "scope" },
      { label: "Worker", key: "coding_worker" },
      { label: "Issue", render: (row) => row.issue_id || "n/a" },
      { label: "Tasks", key: "task_count" },
      { label: "Last status", render: (row) => row.last_status || "n/a" },
      { label: "Last started", render: (row) => row.last_started_at ? `${relativeTime(row.last_started_at)}<div class="muted">${row.last_started_at}</div>` : "n/a" },
    ],
    profile.resident_workers,
    "No resident worker metadata yet.",
  );

  const cooldownTable = renderTable(
    [
      { label: "Provider key", render: (row) => `<div class="mono">${row.provider_key}</div>` },
      { label: "State", render: (row) => `<span class="status-pill ${row.active ? "waiting-provider" : ""}">${row.active ? "cooldown" : "expired"}</span>` },
      { label: "Reason", render: (row) => row.last_reason || "n/a" },
      { label: "Attempts", key: "attempts" },
      { label: "Next attempt", render: (row) => row.next_attempt_at ? `${relativeTime(row.next_attempt_at)}<div class="muted">${row.next_attempt_at}</div>` : "n/a" },
    ],
    profile.provider_cooldowns,
    "No provider cooldowns recorded.",
  );

  const scheduledTable = renderTable(
    [
      { label: "Issue", key: "issue_id" },
      { label: "Interval", render: (row) => `${row.interval_seconds}s` },
      { label: "Next due", render: (row) => row.next_due_at ? `${relativeTime(row.next_due_at)}<div class="muted">${row.next_due_at}</div>` : "n/a" },
      { label: "Last started", render: (row) => row.last_started_at ? `${relativeTime(row.last_started_at)}<div class="muted">${row.last_started_at}</div>` : "n/a" },
    ],
    profile.scheduled_issues,
    "No scheduled issue state recorded.",
  );

  const queueTable = renderTable(
    [
      { label: "Issue", key: "issue_id" },
      { label: "Session", render: (row) => row.session ? `<div class="mono">${row.session}</div>` : "n/a" },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${row.updated_at}</div>` : "n/a" },
    ],
    profile.issue_queue.pending,
    "No pending leased issues.",
  );

  return `
    <article class="profile">
      <header class="profile-header">
        <div>
          <div class="profile-title">
            <h2>${profile.id}</h2>
            <span class="badge">${profile.repo_slug || "repo slug unavailable"}</span>
          </div>
          <div class="profile-subtitle mono">${profile.runs_root}</div>
        </div>
        <div class="badge-row">${providerBadges}</div>
      </header>
      <section class="overview">${summaryCards}</section>
      <section class="profile-grid">
        <section class="panel">
          <h3>Active Runs</h3>
          <p class="panel-subtitle">Lifecycle shows technical session completion. Result shows what the run achieved: implemented, reported, or blocked.</p>
          ${runsTable}
        </section>
        <section class="panel">
          <h3>Resident Controllers</h3>
          <p class="panel-subtitle">Includes provider wait and failover telemetry. Stale controllers show a warning.</p>
          ${controllerTable}
        </section>
        <section class="panel half">
          <h3>Issue Retries</h3>
          ${retryTable}
        </section>
        <section class="panel">
          <h3>Resident Worker Metadata</h3>
          ${workerTable}
        </section>
        <section class="panel half">
          <h3>Provider Cooldowns</h3>
          ${cooldownTable}
        </section>
        <section class="panel half">
          <h3>Scheduled Issues</h3>
          ${scheduledTable}
        </section>
        <section class="panel half">
          <h3>Pending Issue Queue</h3>
          ${queueTable}
        </section>
      </section>
    </article>
  `;
}

async function loadSnapshot() {
  refreshButton.disabled = true;
  try {
    const response = await fetch("./api/snapshot.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Snapshot request failed with ${response.status}`);
    }
    const snapshot = await response.json();
    generatedAtNode.textContent = `Snapshot: ${snapshot.generated_at}`;
    renderOverview(snapshot);
    profilesNode.innerHTML = snapshot.profiles.map(renderProfile).join("");
  } catch (error) {
    generatedAtNode.textContent = `Snapshot load failed: ${error.message}`;
    profilesNode.innerHTML = `<article class="profile"><div class="empty-state">${error.message}</div></article>`;
  } finally {
    refreshButton.disabled = false;
  }
}

refreshButton.addEventListener("click", () => {
  void loadSnapshot();
});

void loadSnapshot();
window.setInterval(() => {
  void loadSnapshot();
}, 5000);
