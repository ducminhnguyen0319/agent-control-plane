const refreshButton = document.querySelector("#refresh-button");
const themeToggleButton = document.querySelector("#theme-toggle");
const generatedAtNode = document.querySelector("#generated-at");
const overviewNode = document.querySelector("#overview");
const profilesNode = document.querySelector("#profiles");
const seenAlertIds = new Set();
let notificationPermissionRequested = false;
const THEME_STORAGE_KEY = "acp-dashboard-theme";
const ROWS_PER_PAGE = 10;

// Pagination state: { [tableId]: { page: number } }
window._acpPagination = {};

function systemPrefersDark() {
  return typeof window.matchMedia === "function" && window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function currentThemePreference() {
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    if (stored === "light" || stored === "dark") return stored;
  } catch (_error) {
    // Ignore storage access issues and fall back to system preference.
  }
  return systemPrefersDark() ? "dark" : "light";
}

function updateThemeToggleLabel(theme) {
  if (!themeToggleButton) return;
  const nextTheme = theme === "dark" ? "light" : "dark";
  const label = nextTheme === "dark" ? "Dark mode" : "Light mode";
  themeToggleButton.textContent = label;
  themeToggleButton.setAttribute("aria-label", `Switch to ${label.toLowerCase()}`);
}

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  updateThemeToggleLabel(theme);
}

function persistTheme(theme) {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch (_error) {
    // Ignore storage access issues.
  }
}

function initializeTheme() {
  applyTheme(currentThemePreference());
  if (!themeToggleButton) return;
  themeToggleButton.addEventListener("click", () => {
    const nextTheme = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    applyTheme(nextTheme);
    persistTheme(nextTheme);
  });
}

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

function formatCompactDate(input) {
  if (!input) return "n/a";
  const d = new Date(input);
  if (Number.isNaN(d.getTime())) return input;
  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

function formatDuration(seconds) {
  if (!seconds && seconds !== 0) return "n/a";
  const absSeconds = Math.abs(seconds);
  const parts = [];
  const units = [
    [86400, "d"],
    [3600, "h"],
    [60, "m"],
    [1, "s"],
  ];
  for (const [unitSeconds, label] of units) {
    if (absSeconds >= unitSeconds) {
      const amount = Math.floor(absSeconds / unitSeconds);
      parts.push(`${amount}${label}`);
      seconds -= amount * unitSeconds;
    }
  }
  return parts.slice(0, 2).join(" ") || "0s";
}

function timeRemaining(isoString) {
  if (!isoString) return "n/a";
  const next = new Date(isoString);
  if (Number.isNaN(next.getTime())) return isoString;
  const diffSeconds = Math.round((next.getTime() - Date.now()) / 1000);
  if (diffSeconds <= 0) return "ready now";
  return formatDuration(diffSeconds);
}

function statusClass(status) {
  if (!status) return "";
  return status.replace(/[^a-zA-Z0-9_-]/g, "-");
}

function renderLifecycle(row) {
  const note = row.result_only_completion === "yes" ? `<div class="muted">Recovered</div>` : "";
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
      acc.alerts += profile.counts.alerts || 0;
      acc.pendingGithubWrites += profile.counts.pending_github_writes || 0;
      return acc;
    },
    { activeRuns: 0, runningRuns: 0, implementedRuns: 0, reportedRuns: 0, blockedRuns: 0, controllers: 0, cooldowns: 0, queue: 0, alerts: 0, pendingGithubWrites: 0 },
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
    ["Pending GitHub Writes", totals.pendingGithubWrites],
    ["Alerts", totals.alerts],
    ["Queued Issues", totals.queue],
    ["Retries", totals.retries || 0],
    ["Blockers", totals.blockers || 0],
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

// Build windowed pagination: max 5 page buttons with ellipsis
function buildWindowedPages(current, total) {
  const pages = [];
  const maxVisible = 5;
  if (total <= maxVisible) {
    for (let i = 1; i <= total; i++) pages.push(i);
    return pages;
  }
  // Always show first, last, and surrounding pages
  const pagesSet = new Set();
  pagesSet.add(1);
  pagesSet.add(total);
  for (let i = Math.max(1, current - 1); i <= Math.min(total, current + 1); i++) {
    pagesSet.add(i);
  }
  const sorted = Array.from(pagesSet).sort((a, b) => a - b);
  // Add ellipsis markers
  const result = [];
  let prev = 0;
  for (const p of sorted) {
    if (p - prev > 1) result.push("...");
    result.push(p);
    prev = p;
  }
  return result;
}

function renderPagination(tableId, currentPage, totalPages, totalRows) {
  if (totalPages <= 1) return "";
  const start = (currentPage - 1) * ROWS_PER_PAGE + 1;
  const end = Math.min(currentPage * ROWS_PER_PAGE, totalRows);
  const pages = buildWindowedPages(currentPage, totalPages);
  const buttons = pages
    .map((p) => {
      if (p === "...") return `<span class="pagination-ellipsis">…</span>`;
      return `<button class="${p === currentPage ? "active" : ""}" onclick="window._acpGoToPage('${tableId}',${p})">${p}</button>`;
    })
    .join("");
  return `
    <div class="pagination">
      <span class="pagination-info">Showing ${start}-${end} of ${totalRows}</span>
      <div class="pagination-controls">
        <button ${currentPage <= 1 ? "disabled" : ""} onclick="window._acpGoToPage('${tableId}',${currentPage - 1})">‹</button>
        ${buttons}
        <button ${currentPage >= totalPages ? "disabled" : ""} onclick="window._acpGoToPage('${tableId}',${currentPage + 1})">›</button>
      </div>
    </div>`;
}

window._acpGoToPage = function(tableId, page) {
  window._acpPagination[tableId] = { page };
  rerenderAll();
};

function renderTableWithPagination(tableId, columns, rows, emptyMessage = "No data right now.") {
  if (!rows.length) {
    return `<div class="empty-state">${emptyMessage}</div>`;
  }
  const state = window._acpPagination[tableId] || { page: 1 };
  let { page } = state;
  const totalPages = Math.ceil(rows.length / ROWS_PER_PAGE);
  if (page < 1) page = 1;
  if (page > totalPages) page = totalPages;
  window._acpPagination[tableId] = { page };
  const start = (page - 1) * ROWS_PER_PAGE;
  const pageRows = rows.slice(start, start + ROWS_PER_PAGE);
  const headers = columns.map((column) => `<th>${column.label}</th>`).join("");
  const body = pageRows
    .map((row) => {
      const cells = columns
        .map((column) => `<td>${column.render ? column.render(row) : row[column.key] ?? ""}</td>`)
        .join("");
      return `<tr>${cells}</tr>`;
    })
    .join("");
  const paginationHtml = renderPagination(tableId, page, totalPages, rows.length);
  return `<div class="table-wrap"><table><thead><tr>${headers}</tr></thead><tbody>${body}</tbody></table></div>${paginationHtml}`;
}

function renderAlerts(alerts) {
  if (!alerts.length) {
    return `<div class="empty-state">No active alerts for this profile.</div>`;
  }
  return `
    <div class="alert-list">
      ${alerts
        .map(
          (alert) => `
            <article class="alert-card ${statusClass(alert.severity || "warn")}">
              <div class="alert-header">
                <div>
                  <h4>${alert.title}</h4>
                  <div class="muted mono">${alert.session || "n/a"} · ${alert.task_kind || "task"} ${alert.task_id || ""}</div>
                </div>
                <span class="badge warn">${alert.kind}</span>
              </div>
              <p>${alert.message}</p>
              <div class="alert-meta">
                <span>${alert.reset_at ? `Reset: ${formatCompactDate(alert.reset_at)}` : "Reset: n/a"}</span>
                <span>${alert.updated_at ? `${relativeTime(alert.updated_at)} · ${formatCompactDate(alert.updated_at)}` : "updated n/a"}</span>
              </div>
            </article>
          `,
        )
        .join("")}
    </div>
  `;
}

function renderCodexRotation(rotation) {
  if (!rotation || !rotation.active_label) {
    return `<div class="empty-state">Codex rotation data is not available yet for this Codex profile.</div>`;
  }
  const candidates = (rotation.candidate_labels || []).length ? rotation.candidate_labels.join(", ") : "n/a";
  const ready = (rotation.ready_candidates || []).length ? rotation.ready_candidates.join(", ") : "none";
  const nextRetry = rotation.next_retry_at
    ? `${rotation.next_retry_label || "n/a"} · ${relativeTime(rotation.next_retry_at)}<div class="muted">${formatCompactDate(rotation.next_retry_at)}</div>`
    : "n/a";
  const lastSwitch = rotation.last_switch_label
    ? `${rotation.last_switch_label}${rotation.last_switch_reason ? ` · ${rotation.last_switch_reason}` : ""}`
    : "n/a";

  return renderTableWithPagination(
    "codex-rotation",
    [
      { label: "Current", render: () => `<div class="mono">${rotation.active_label}</div>` },
      { label: "Decision", render: () => `<span class="status-pill ${statusClass(rotation.switch_decision || "unknown")}">${rotation.switch_decision || "unknown"}</span>` },
      { label: "Candidates", render: () => `<div class="mono">${candidates}</div>` },
      { label: "Ready now", render: () => `<div class="mono">${ready}</div>` },
      { label: "Next retry", render: () => nextRetry },
      { label: "Last switch", render: () => `<div class="mono">${lastSwitch}</div>` },
    ],
    [{}],
    "No Codex rotation data for this profile.",
  );
}

function renderProfile(profile) {
  const providerBadges = [
    profile.coding_worker ? `<span class="badge good">${profile.coding_worker}</span>` : "",
    profile.provider_pool.backend
      ? `<span class="badge">${profile.provider_pool.backend}: ${profile.provider_pool.model || "n/a"}</span>`
      : "",
    profile.provider_pool.name ? `<span class="badge">${profile.provider_pool.name}</span>` : "",
    profile.provider_pool.pools_exhausted
      ? `<span class="badge warn">pools exhausted</span>`
      : "",
    profile.provider_pool.last_reason ? `<span class="badge warn">${profile.provider_pool.last_reason}</span>` : "",
  ]
    .filter(Boolean)
    .join("");

  const summaryCards = [
    ["Run sessions", profile.counts.active_runs],
    ["Running", profile.counts.running_runs],
    ["Recent completed", profile.counts.recent_history_runs || 0],
    ["Implemented", profile.counts.implemented_runs],
    ["Reported", profile.counts.reported_runs],
    ["Blocked", profile.counts.blocked_runs],
    ["Live controllers", profile.counts.live_resident_controllers],
    ["Stale controllers", profile.counts.stale_resident_controllers],
    ["Provider cooldowns", profile.counts.provider_cooldowns],
    ["Pending GitHub writes", profile.counts.pending_github_writes || 0],
    ["Failed GitHub writes", profile.counts.failed_github_writes || 0],
    ["Alerts", profile.counts.alerts || 0],
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

  const runsFilterState = window._acpRunsFilter || { search: "", status: "all" };
  window._acpRunsFilter = runsFilterState;

  const filteredRuns = profile.runs.filter((row) => {
    if (runsFilterState.status !== "all" && row.status !== runsFilterState.status) return false;
    if (runsFilterState.search) {
      const q = runsFilterState.search.toLowerCase();
      return (
        (row.session || "").toLowerCase().includes(q) ||
        (row.coding_worker || "").toLowerCase().includes(q) ||
        (row.task_kind || "").toLowerCase().includes(q) ||
        (row.task_id || "").toLowerCase().includes(q)
      );
    }
    return true;
  });

  const runsTable = renderTableWithPagination(
    `runs-${profile.id}`,
    [
      { label: "Session", render: (row) => `<div class="mono">${row.session}</div>` },
      { label: "Task", render: (row) => `${row.task_kind || "n/a"} ${row.task_id || ""}`.trim() },
      { label: "Lifecycle", render: renderLifecycle },
      { label: "Worker", key: "coding_worker" },
      { label: "Provider", render: (row) => row.provider_model || "n/a" },
      { label: "Result", render: renderResult },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${formatCompactDate(row.updated_at)}</div>` : "n/a" },
    ],
    filteredRuns,
    "No active run directories for this profile.",
  );

  const historyFilterState = window._acpHistoryFilter || { search: "", result: "all" };
  window._acpHistoryFilter = historyFilterState;

  const filteredHistory = (profile.recent_history || []).filter((row) => {
    if (historyFilterState.result !== "all" && row.result_kind !== historyFilterState.result) return false;
    if (historyFilterState.search) {
      const q = historyFilterState.search.toLowerCase();
      return (
        (row.session || "").toLowerCase().includes(q) ||
        (row.coding_worker || "").toLowerCase().includes(q) ||
        (row.task_kind || "").toLowerCase().includes(q)
      );
    }
    return true;
  });

  const recentHistoryTable = renderTableWithPagination(
    `history-${profile.id}`,
    [
      { label: "Session", render: (row) => `<div class="mono">${row.session}</div>` },
      { label: "Task", render: (row) => `${row.task_kind || "n/a"} ${row.task_id || ""}`.trim() },
      { label: "Lifecycle", render: renderLifecycle },
      { label: "Worker", key: "coding_worker" },
      { label: "Result", render: renderResult },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${formatCompactDate(row.updated_at)}</div>` : "n/a" },
    ],
    filteredHistory,
    "No recently archived runs.",
  );

  const controllerTable = renderTableWithPagination(
    `controllers-${profile.id}`,
    [
      { label: "Issue", key: "issue_id" },
      { label: "State", render: renderControllerState },
      { label: "Lane", render: (row) => `${row.lane_kind || "n/a"} / ${row.lane_value || "n/a"}` },
      { label: "Reason", render: (row) => row.reason || "n/a" },
      { label: "Provider", render: (row) => `${row.provider_backend || "n/a"} ${row.provider_model || ""}`.trim() },
      { label: "Failover", render: (row) => `${row.provider_failover_count} failovers / ${row.provider_switch_count} switches` },
      { label: "Wait", render: (row) => `${row.provider_wait_count} waits / ${row.provider_wait_total_seconds}s` },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${formatCompactDate(row.updated_at)}</div>` : "n/a" },
    ],
    profile.resident_controllers,
    "No resident controllers recorded for this profile.",
  );

  const retryTable = renderTableWithPagination(
    `retries-${profile.id}`,
    [
      { label: "Issue", key: "issue_id" },
      { label: "Status", render: (row) => `<span class="status-pill ${row.ready ? "" : "waiting-provider"}">${row.ready ? "ready" : "retrying"}</span>` },
      { label: "Reason", render: (row) => row.last_reason || "n/a" },
      { label: "Attempts", key: "attempts" },
      { label: "Next attempt", render: (row) => row.next_attempt_at ? `${relativeTime(row.next_attempt_at)}<div class="muted">${formatCompactDate(row.next_attempt_at)}</div>` : "n/a" },
      { label: "Time Remaining", render: (row) => row.next_attempt_at ? timeRemaining(row.next_attempt_at) : "n/a" },
    ],
    profile.issue_retries || [],
    "No issue retries recorded.",
  );

  const prRetryTable = renderTableWithPagination(
    `pr-retries-${profile.id}`,
    [
      { label: "PR", key: "pr_number" },
      { label: "Status", render: (row) => `<span class="status-pill ${row.ready ? "" : "waiting-provider"}">${row.ready ? "ready" : "retrying"}</span>` },
      { label: "Reason", render: (row) => row.last_reason || "n/a" },
      { label: "Attempts", key: "attempts" },
      { label: "Next attempt", render: (row) => row.next_attempt_at ? `${relativeTime(row.next_attempt_at)}<div class="muted">${formatCompactDate(row.next_attempt_at)}</div>` : "n/a" },
      { label: "Time Remaining", render: (row) => row.next_attempt_at ? timeRemaining(row.next_attempt_at) : "n/a" },
    ],
    profile.pr_retries || [],
    "No PR retries recorded.",
  );

  const workerTable = renderTableWithPagination(
    `workers-${profile.id}`,
    [
      { label: "Key", render: (row) => `<div class="mono">${row.key}</div>` },
      { label: "Scope", key: "scope" },
      { label: "Worker", key: "coding_worker" },
      { label: "Issue", render: (row) => row.issue_id || "n/a" },
      { label: "Lane", render: (row) => `${row.resident_lane_kind || "n/a"} / ${row.resident_lane_value || "n/a"}` },
      { label: "Tasks", key: "task_count" },
      { label: "Last status", render: (row) => row.last_status || "n/a" },
      { label: "Last started", render: (row) => row.last_started_at ? `${relativeTime(row.last_started_at)}<div class="muted">${formatCompactDate(row.last_started_at)}</div>` : "n/a" },
    ],
    profile.resident_workers,
    "No resident worker metadata yet.",
  );

  const cooldownTable = renderTableWithPagination(
    `cooldowns-${profile.id}`,
    [
      { label: "Provider key", render: (row) => `<div class="mono">${row.provider_key}</div>` },
      { label: "State", render: (row) => `<span class="status-pill ${row.active ? "waiting-provider" : ""}">${row.active ? "cooldown" : "expired"}</span>` },
      { label: "Reason", render: (row) => row.last_reason || "n/a" },
      { label: "Attempts", key: "attempts" },
      { label: "Next attempt", render: (row) => row.next_attempt_at ? `${relativeTime(row.next_attempt_at)}<div class="muted">${formatCompactDate(row.next_attempt_at)}</div>` : "n/a" },
      { label: "Time Remaining", render: (row) => row.next_attempt_at ? timeRemaining(row.next_attempt_at) : "n/a" },
    ],
    profile.provider_cooldowns,
    "No provider cooldowns recorded.",
  );

  const scheduledTable = renderTableWithPagination(
    `scheduled-${profile.id}`,
    [
      { label: "Issue", key: "issue_id" },
      { label: "Interval", render: (row) => `${row.interval_seconds}s` },
      { label: "Next due", render: (row) => row.next_due_at ? `${relativeTime(row.next_due_at)}<div class="muted">${formatCompactDate(row.next_due_at)}</div>` : "n/a" },
      { label: "Time Remaining", render: (row) => row.next_due_at ? timeRemaining(row.next_due_at) : "n/a" },
      { label: "Last started", render: (row) => row.last_started_at ? `${relativeTime(row.last_started_at)}<div class="muted">${formatCompactDate(row.last_started_at)}</div>` : "n/a" },
    ],
    profile.scheduled_issues,
    "No scheduled issue state recorded.",
  );

  const queueTable = renderTableWithPagination(
    `queue-${profile.id}`,
    [
      { label: "Issue", key: "issue_id" },
      { label: "Session", render: (row) => row.session ? `<div class="mono">${row.session}</div>` : "n/a" },
      { label: "Queued by", key: "queued_by" },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${formatCompactDate(row.updated_at)}</div>` : "n/a" },
    ],
    profile.issue_queue.pending,
    "No pending leased issues.",
  );

  const claimsTable = renderTableWithPagination(
    `claims-${profile.id}`,
    [
      { label: "Issue", key: "issue_id" },
      { label: "Session", render: (row) => row.session ? `<div class="mono">${row.session}</div>` : "n/a" },
      { label: "Claimed by", key: "claimer" },
      { label: "Updated", render: (row) => row.updated_at ? `${relativeTime(row.updated_at)}<div class="muted">${formatCompactDate(row.updated_at)}</div>` : "n/a" },
    ],
    profile.issue_queue.claims || [],
    "No claimed issues.",
  );

  const githubOutbox = profile.github_outbox || { counts: {}, pending: [] };
  const githubOutboxTable = renderTableWithPagination(
    `github-outbox-${profile.id}`,
    [
      { label: "Type", render: (row) => row.type || "n/a" },
      { label: "Target", render: (row) => `${row.kind || row.type || "write"} #${row.number || "?"}` },
      {
        label: "Payload",
        render: (row) => {
          if (row.type === "labels") {
            return `+${row.add_count || 0} / -${row.remove_count || 0}`;
          }
          return row.body_preview || "n/a";
        },
      },
      { label: "Created", render: (row) => row.created_at ? `${relativeTime(row.created_at)}<div class="muted">${formatCompactDate(row.created_at)}</div>` : "n/a" },
    ],
    githubOutbox.pending || [],
    "No pending GitHub write intents.",
  );

  const codexRotationPanel =
    profile.coding_worker === "codex"
      ? `
        <section class="panel">
          <h3>Codex Rotation</h3>
          <p class="panel-subtitle">Shows the active Codex label, candidate labels, and whether failover is ready or deferred.</p>
          ${renderCodexRotation(profile.codex_rotation)}
        </section>
      `
      : "";

  const runsFilterBar = `
    <div class="filter-bar">
      <input type="text" class="filter-search" placeholder="Search runs..." value="${runsFilterState.search}"
        oninput="window._acpRunsFilter.search=this.value; rerenderAll();" />
      <button class="filter-btn ${runsFilterState.status === 'all' ? 'active' : ''}" onclick="window._acpRunsFilter.status='all'; rerenderAll();">All</button>
      <button class="filter-btn ${runsFilterState.status === 'RUNNING' ? 'active' : ''}" onclick="window._acpRunsFilter.status='RUNNING'; rerenderAll();">Running</button>
      <button class="filter-btn ${runsFilterState.status === 'SUCCEEDED' ? 'active' : ''}" onclick="window._acpRunsFilter.status='SUCCEEDED'; rerenderAll();">Completed</button>
      <button class="filter-btn ${runsFilterState.status === 'FAILED' ? 'active' : ''}" onclick="window._acpRunsFilter.status='FAILED'; rerenderAll();">Failed</button>
    </div>
  `;

  const historyFilterBar = `
    <div class="filter-bar">
      <input type="text" class="filter-search" placeholder="Search history..." value="${historyFilterState.search}"
        oninput="window._acpHistoryFilter.search=this.value; rerenderAll();" />
      <button class="filter-btn ${historyFilterState.result === 'all' ? 'active' : ''}" onclick="window._acpHistoryFilter.result='all'; rerenderAll();">All</button>
      <button class="filter-btn ${historyFilterState.result === 'implemented' ? 'active' : ''}" onclick="window._acpHistoryFilter.result='implemented'; rerenderAll();">Implemented</button>
      <button class="filter-btn ${historyFilterState.result === 'reported' ? 'active' : ''}" onclick="window._acpHistoryFilter.result='reported'; rerenderAll();">Reported</button>
      <button class="filter-btn ${historyFilterState.result === 'blocked' ? 'active' : ''}" onclick="window._acpHistoryFilter.result='blocked'; rerenderAll();">Blocked</button>
    </div>
  `;

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
          <h3>Host Alerts</h3>
          <p class="panel-subtitle">High-signal operational blockers surfaced from active run logs and comment artifacts.</p>
          ${renderAlerts(profile.alerts || [])}
        </section>
        <section class="panel">
          <h3>Active Runs</h3>
          <p class="panel-subtitle">Lifecycle shows technical session completion. Result shows what the run achieved: implemented, reported, or blocked.</p>
          ${runsFilterBar}
          ${runsTable}
        </section>
        <section class="panel">
          <h3>Recent Completed Runs</h3>
          <p class="panel-subtitle">Recently archived runs so they do not disappear from the dashboard immediately after completion.</p>
          ${historyFilterBar}
          ${recentHistoryTable}
        </section>
        <section class="panel">
          <h3>Resident Controllers</h3>
          <p class="panel-subtitle">Includes provider wait and failover telemetry. Stale controllers show a warning.</p>
          ${controllerTable}
        </section>
        ${codexRotationPanel}
        <section class="panel half">
          <h3>Issue Retries</h3>
          ${retryTable}
        </section>
        <section class="panel half">
          <h3>PR Retries</h3>
          ${prRetryTable}
        </section>
        <section class="panel">
          <h3>Resident Worker Metadata</h3>
          ${workerTable}
        </section>
        <section class="panel">
          <h3>Troubleshooting</h3>
          <p class="panel-subtitle">Run diagnostics or debugging tools against this live profile.</p>
          <div class="action-bar">
            <button class="action-btn" onclick="runDoctor('${profile.id}')">🔧 Run Doctor</button>
            <button class="action-btn" onclick="exportProfile('${profile.id}')">📤 Export</button>
            <button class="action-btn" onclick="document.getElementById('import-file-${profile.id}').click()">📥 Import</button>
            <input type="file" id="import-file-${profile.id}" style="display:none" accept=".json" onchange="importProfile('${profile.id}', this)">
            <span id="doctor-status-${profile.id}"></span>
          </div>
          <pre id="doctor-output-${profile.id}" class="doctor-output" style="display:none;"></pre>
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
        <section class="panel half">
          <h3>Claimed Issues</h3>
          ${claimsTable}
        </section>
        <section class="panel">
          <h3>GitHub Outbox</h3>
          <p class="panel-subtitle">Local write intents queued while ACP defers or retries GitHub sync. Pending ${githubOutbox.counts?.pending || 0}, sent ${githubOutbox.counts?.sent || 0}, failed ${githubOutbox.counts?.failed || 0}.</p>
          ${githubOutboxTable}
        </section>
      </section>
    </article>
  `;
}

async function maybeNotifyAlerts(snapshot) {
  const alerts = (snapshot.alerts || []).filter((alert) => alert && alert.id);
  if (!alerts.length || typeof window.Notification === "undefined") return;

  if (window.Notification.permission === "default" && !notificationPermissionRequested) {
    notificationPermissionRequested = true;
    try {
      await window.Notification.requestPermission();
    } catch (_error) {
      return;
    }
  }

  if (window.Notification.permission !== "granted") return;

  for (const alert of alerts) {
    if (seenAlertIds.has(alert.id)) continue;
    seenAlertIds.add(alert.id);
    const bodyParts = [];
    if (alert.session) bodyParts.push(alert.session);
    if (alert.reset_at) bodyParts.push(`reset ${alert.reset_at}`);
    if (alert.message) bodyParts.push(alert.message);
    new window.Notification(alert.title || "ACP alert", {
      body: bodyParts.join(" · ").slice(0, 240),
      tag: alert.id,
    });
  }
}

async function loadSnapshot() {
  refreshButton.disabled = true;
  try {
    const response = await fetch("./api/snapshot.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Snapshot request failed with ${response.status}`);
    }
    const snapshot = await response.json();
    window._acpSnapshot = snapshot;
    renderFromSnapshot(snapshot);
    await maybeNotifyAlerts(snapshot);
  } catch (error) {
    generatedAtNode.textContent = `Snapshot load failed: ${error.message}`;
    profilesNode.innerHTML = `<article class="profile"><div class="empty-state">${error.message}</div></article>`;
  } finally {
    refreshButton.disabled = false;
  }
}

function renderFromSnapshot(snapshot) {
  generatedAtNode.textContent = `Snapshot: ${formatCompactDate(snapshot.generated_at)}`;
  renderOverview(snapshot);
  profilesNode.innerHTML = snapshot.profiles.map(renderProfile).join("");
}

function rerenderAll() {
  const snapshot = window._acpSnapshot;
  if (!snapshot) return;
  renderFromSnapshot(snapshot);
}

async function runDoctor(profileId) {
  const statusEl = document.getElementById(`doctor-status-${profileId}`);
  const outputEl = document.getElementById(`doctor-output-${profileId}`);
  if (statusEl) statusEl.textContent = "Running...";
  if (outputEl) {
    outputEl.style.display = "none";
    outputEl.textContent = "";
  }
  try {
    const response = await fetch(`/api/doctor?profile_id=${encodeURIComponent(profileId)}`, { cache: "no-store" });
    const data = await response.json();
    if (statusEl) statusEl.textContent = response.ok ? "Done" : `Error: ${data.error || response.status}`;
    if (outputEl) {
      outputEl.style.display = "block";
      outputEl.textContent = data.output || data.error || "No output";
    }
  } catch (error) {
    if (statusEl) statusEl.textContent = `Error: ${error.message}`;
  }
}

async function exportProfile(profileId) {
  try {
    const response = await fetch(`/api/profile/export?profile_id=${encodeURIComponent(profileId)}`, { cache: "no-store" });
    if (!response.ok) {
      const data = await response.json();
      alert(`Export failed: ${data.error || response.status}`);
      return;
    }
    const data = await response.json();
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `acp-profile-${profileId}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  } catch (error) {
    alert(`Export failed: ${error.message}`);
  }
}

async function importProfile(profileId, inputEl) {
  const file = inputEl.files[0];
  if (!file) return;
  
  try {
    const text = await file.text();
    const data = JSON.parse(text);
    
    if (!data.profile_id || !data.config) {
      alert("Invalid profile file: missing profile_id or config");
      return;
    }
    
    const response = await fetch("/api/profile/import", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    
    const result = await response.json();
    if (response.ok) {
      alert(`Profile ${profileId} imported successfully!`);
      setTimeout(() => window.location.reload(), 1000);
    } else {
      alert(`Import failed: ${result.error || response.status}`);
    }
  } catch (error) {
    alert(`Import failed: ${error.message}`);
  } finally {
    inputEl.value = "";
  }
}

refreshButton.addEventListener("click", () => {
  void loadSnapshot();
});

initializeTheme();
void loadSnapshot();

// WebSocket live updates
let wsReconnectDelay = 1000;
let wsConnectionActive = false;
let wsReconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 10;

function updateConnectionStatus(connected) {
  const statusEl = document.getElementById('ws-status');
  if (!statusEl) return;
  if (connected) {
    statusEl.textContent = '● Live';
    statusEl.className = 'connection-status connected';
    wsReconnectAttempts = 0;
  } else {
    statusEl.textContent = `● Reconnecting (${wsReconnectAttempts})`;
    statusEl.className = 'connection-status disconnected';
  }
}

function connectWebSocket() {
  const protocol = location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl = `${protocol}//${location.host}/ws`;
  const ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    wsReconnectDelay = 1000;
    wsConnectionActive = true;
    wsReconnectAttempts++;
    updateConnectionStatus(true);
    console.log("ACP Dashboard: WebSocket connected");
  };

  ws.onmessage = async (event) => {
    try {
      let data = event.data;
      // Handle Blob (binary) or string
      if (data instanceof Blob) {
        data = await data.text();
      }
      const snapshot = JSON.parse(data);
      window._acpSnapshot = snapshot;
      renderFromSnapshot(snapshot);
      maybeNotifyAlerts(snapshot);
    } catch (error) {
      console.error("ACP Dashboard: Failed to parse WebSocket message", error);
    }
  };

  ws.onclose = () => {
    wsConnectionActive = false;
    wsReconnectAttempts++;
    updateConnectionStatus(false);
    console.log(`ACP Dashboard: WebSocket disconnected, reconnecting in ${wsReconnectDelay}ms`);
    if (wsReconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      console.error(`ACP Dashboard: Max reconnection attempts (${MAX_RECONNECT_ATTEMPTS}) reached`);
      return;
    }
    setTimeout(connectWebSocket, wsReconnectDelay);
    wsReconnectDelay = Math.min(wsReconnectDelay * 2, 30000);
  };

  ws.onerror = (error) => {
    console.error("ACP Dashboard: WebSocket error", error);
  };
}

connectWebSocket();

// Scheduler Status
let schedulerStatus = null;

function exportSnapshot() {
  if (!window._acpSnapshot) {
    alert('No snapshot data available yet.');
    return;
  }
  const dataStr = JSON.stringify(window._acpSnapshot, null, 2);
  const dataBlob = new Blob([dataStr], { type: 'application/json' });
  const url = URL.createObjectURL(dataBlob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `acp-snapshot-${new Date().toISOString().slice(0, 10)}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

async function fetchSchedulerStatus() {
  try {
    const response = await fetch("/api/scheduler-status", { cache: "no-store" });
    if (response.ok) {
      schedulerStatus = await response.json();
      renderSchedulerStatus();
    }
  } catch (error) {
    console.error("ACP Dashboard: Failed to fetch scheduler status", error);
  }
}

function renderSchedulerStatus() {
  const container = document.getElementById("scheduler-status");
  if (!container) return;
  if (!schedulerStatus) {
    container.innerHTML = `<article class="profile"><h3>Scheduler Status</h3><p class="panel-subtitle">Loading scheduler status...</p></article>`;
    return;
  }
  const { is_running, pid, last_log_lines, message } = schedulerStatus;
  const statusPill = is_running
    ? `<span class="status-pill RUNNING">Running (PID: ${pid})</span>`
    : `<span class="status-pill STOPPED">Stopped</span>`;
  const logHtml = last_log_lines && last_log_lines.length
    ? `<pre class="mono" style="background:var(--panel-strong); padding:8px; border-radius:4px; font-size:11px; max-height:120px; overflow-y:auto;">${last_log_lines.join("\n")}</pre>`
    : `<p class="muted">No log data available.</p>`;
  container.innerHTML = `
    <article class="profile">
      <header class="profile-header">
        <div>
          <div class="profile-title">
            <h2>Scheduler Status</h2>
            ${statusPill}
          </div>
          <p class="panel-subtitle">${message || "Scheduler status from real state"}</p>
        </div>
      </header>
      <section class="panel">
        <h3>Last Log Lines</h3>
        ${logHtml}
      </section>
    </article>
  `;
}

// Initial load
fetchSchedulerStatus();
setInterval(fetchSchedulerStatus, 30000); // Refresh every 30s
