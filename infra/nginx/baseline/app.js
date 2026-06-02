const params = new URLSearchParams(window.location.search);
const project = params.get("project") || "shipment-status-agile-demo";
const dataRoot = `/baseline-data/${encodeURIComponent(project)}`;

const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, char => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
}[char]));

const display = value => value === null || value === undefined || value === "" ? "-" : value;
const cell = (oldValue, newValue) => oldValue === newValue
  ? escapeHtml(display(newValue))
  : `<span class="old">${escapeHtml(display(oldValue))}</span>${escapeHtml(display(newValue))}`;
const ticketCell = (id, oldValue, newValue) => {
  const format = value => value ? `#${id} ${value}` : value;
  return cell(format(oldValue), format(newValue));
};

async function loadJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return response.json();
}

function durationToHours(duration) {
  if (duration === null || duration === undefined || duration === "") return null;
  if (typeof duration === "number") return duration;
  const match = String(duration).match(/^P(?:(\d+(?:\.\d+)?)D)?T?(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$/);
  if (!match) return null;
  return Number(match[1] || 0) * 24 + Number(match[2] || 0) + Number(match[3] || 0) / 60 + Number(match[4] || 0) / 3600;
}

async function loadCurrentPlan() {
  const response = await fetch(`/api/v3/projects/${encodeURIComponent(project)}/work_packages?pageSize=1000`, {
    credentials: "same-origin",
    headers: { Accept: "application/hal+json" }
  });
  if (!response.ok) {
    throw new Error("現在計画を取得できません。OpenProjectへログインしてから再読み込みしてください。");
  }
  const data = await response.json();
  const items = data._embedded?.elements || [];
  const workPackages = items.map(item => ({
    id: item.id,
    subject: item.subject,
    type: item._links?.type?.title || null,
    status: item._links?.status?.title || null,
    assignee: item._links?.assignee?.title || null,
    start_date: item.startDate || null,
    due_date: item.dueDate || null,
    estimated_hours: durationToHours(item.estimatedTime ?? item.derivedEstimatedTime),
    parent_id: item._links?.parent?.href?.split("/").pop() || null
  }));
  return {
    project_identifier: project,
    project_name: document.querySelector("#project-name").textContent || project,
    captured_at: new Date().toISOString(),
    total_estimated_hours: workPackages.reduce((sum, item) => sum + Number(item.estimated_hours || 0), 0),
    work_packages: workPackages
  };
}

function render(baseline, current) {
  const before = new Map(baseline.work_packages.map(item => [item.id, item]));
  const after = new Map(current.work_packages.map(item => [item.id, item]));
  const ids = [...new Set([...before.keys(), ...after.keys()])];
  const fields = ["subject", "assignee", "start_date", "due_date", "estimated_hours", "status"];
  const rows = [];
  let added = 0, removed = 0, changed = 0;

  ids.forEach(id => {
    const oldItem = before.get(id);
    const newItem = after.get(id);
    let kind;
    if (!oldItem) { kind = "added"; added += 1; }
    else if (!newItem) { kind = "removed"; removed += 1; }
    else if (fields.some(field => oldItem[field] !== newItem[field])) { kind = "changed"; changed += 1; }
    else return;

    const oldValue = oldItem || {};
    const newValue = newItem || {};
    rows.push(`
      <tr class="${kind}">
        <td><span class="tag ${kind}">${{ added: "追加", removed: "削除", changed: "変更" }[kind]}</span><br>${escapeHtml(display(newValue.type || oldValue.type))}</td>
        <td>${ticketCell(id, oldValue.subject, newValue.subject)}</td>
        <td>${cell(oldValue.assignee, newValue.assignee)}</td>
        <td>${cell(oldValue.start_date, newValue.start_date)}</td>
        <td>${cell(oldValue.due_date, newValue.due_date)}</td>
        <td>${cell(oldValue.estimated_hours, newValue.estimated_hours)}</td>
        <td>${cell(oldValue.status, newValue.status)}</td>
      </tr>`);
  });

  document.querySelector("#changed-count").textContent = changed;
  document.querySelector("#added-count").textContent = added;
  document.querySelector("#removed-count").textContent = removed;
  const hourDiff = current.total_estimated_hours - baseline.total_estimated_hours;
  document.querySelector("#hours-diff").textContent = `${hourDiff >= 0 ? "+" : ""}${hourDiff}h`;
  document.querySelector("#comparison-body").innerHTML = rows.join("");
  document.querySelector("#empty-message").hidden = rows.length > 0;
  renderGantt(baseline, current);
}

function parseDate(value) {
  return value ? new Date(`${value}T00:00:00Z`) : null;
}

function daysBetween(start, end) {
  return Math.round((end - start) / 86400000);
}

function addDays(date, count) {
  return new Date(date.getTime() + count * 86400000);
}

function renderGantt(baseline, current) {
  const before = new Map(baseline.work_packages.map(item => [item.id, item]));
  const after = new Map(current.work_packages.map(item => [item.id, item]));
  const ids = [...new Set([...before.keys(), ...after.keys()])];
  const dated = ids.map(id => ({ id, oldItem: before.get(id), newItem: after.get(id) }))
    .filter(item => (item.oldItem?.start_date && item.oldItem?.due_date) || (item.newItem?.start_date && item.newItem?.due_date));
  const allDates = dated.flatMap(item => [
    item.oldItem?.start_date, item.oldItem?.due_date, item.newItem?.start_date, item.newItem?.due_date
  ]).filter(Boolean).map(parseDate);
  if (!allDates.length) {
    document.querySelector("#gantt-chart").innerHTML = "<p class='empty'>日付を持つチケットがありません。</p>";
    return;
  }

  const minDate = addDays(new Date(Math.min(...allDates)), -1);
  const maxDate = addDays(new Date(Math.max(...allDates)), 1);
  const totalDays = daysBetween(minDate, maxDate) + 1;
  const percent = date => `${(daysBetween(minDate, parseDate(date)) / totalDays) * 100}%`;
  const width = (start, end) => `${((daysBetween(parseDate(start), parseDate(end)) + 1) / totalDays) * 100}%`;
  const formatHours = hours => hours === null || hours === undefined ? "-" : `${Number(hours)}h`;
  const bar = (item, kind) => item?.start_date && item?.due_date
    ? `<span class="gantt-bar ${kind}" style="left:${percent(item.start_date)};width:${width(item.start_date, item.due_date)}" title="${escapeHtml(item.start_date)} - ${escapeHtml(item.due_date)} / ${formatHours(item.estimated_hours)}"><span class="gantt-bar-label">${formatHours(item.estimated_hours)}</span></span>`
    : "";

  const months = [];
  for (let cursor = new Date(Date.UTC(minDate.getUTCFullYear(), minDate.getUTCMonth(), 1)); cursor <= maxDate; cursor = new Date(Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1))) {
    const visibleStart = cursor < minDate ? minDate : cursor;
    const nextMonth = new Date(Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1));
    const visibleEnd = nextMonth > maxDate ? maxDate : nextMonth;
    months.push(`<span class="gantt-month" style="left:${percent(visibleStart.toISOString().slice(0, 10))};width:${(daysBetween(visibleStart, visibleEnd) / totalDays) * 100}%">${cursor.getUTCFullYear()}/${cursor.getUTCMonth() + 1}</span>`);
  }
  const today = new Date();
  const todayUtc = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
  const todayVisible = todayUtc >= minDate && todayUtc <= maxDate;
  const todayPosition = `${(daysBetween(minDate, todayUtc) / totalDays) * 100}%`;
  const todayLine = todayVisible ? `<span class="gantt-today-line" style="left:${todayPosition}"></span>` : "";
  const todayLabel = todayVisible ? `<span class="gantt-today-label" style="left:${todayPosition}">今日</span>` : "";

  const rows = dated.sort((a, b) => {
    const aDate = a.newItem?.start_date || a.oldItem?.start_date;
    const bDate = b.newItem?.start_date || b.oldItem?.start_date;
    return aDate.localeCompare(bDate) || a.id - b.id;
  }).map(({ id, oldItem, newItem }) => {
    const subject = newItem?.subject || oldItem?.subject;
    const hoursChanged = oldItem && newItem && oldItem.estimated_hours !== newItem.estimated_hours;
    const datesChanged = oldItem && newItem &&
      (oldItem.start_date !== newItem.start_date || oldItem.due_date !== newItem.due_date);
    const changed = hoursChanged || datesChanged;
    const added = !oldItem && newItem;
    const removed = oldItem && !newItem;
    const rowClasses = [
      changed ? "has-change" : "",
      hoursChanged ? "hours-changed" : "",
      datesChanged ? "dates-changed" : "",
      added ? "is-added" : "",
      removed ? "is-removed" : ""
    ].filter(Boolean).join(" ");
    return `
      <div class="gantt-row${rowClasses ? ` ${rowClasses}` : ""}">
        <div class="gantt-label" title="${escapeHtml(subject)}"><strong>#${id}</strong>${escapeHtml(subject)}</div>
        <div class="gantt-timeline" style="--day-width:${100 / totalDays}%">
          ${todayLine}
          ${bar(oldItem, newItem ? "baseline" : "removed")}
          ${bar(newItem, oldItem ? "current" : "added")}
        </div>
      </div>`;
  });

  document.querySelector("#gantt-chart").innerHTML = `
    <div class="gantt-header">
      <div class="gantt-label">チケット</div>
      <div class="gantt-months">${months.join("")}${todayLine}${todayLabel}</div>
    </div>
    ${rows.join("")}`;
}

async function main() {
  const index = await loadJson(`${dataRoot}/index.json`);
  document.querySelector("#project-name").textContent = index.project_name;
  let current;
  try {
    current = await loadCurrentPlan();
  } catch (error) {
    current = await loadJson(`${dataRoot}/current.json`);
    document.querySelector("#snapshot-message").textContent = error.message;
  }
  const select = document.querySelector("#baseline-select");
  document.querySelector("#back-link").href = `/projects/${encodeURIComponent(project)}/gantt`;

  index.baselines.forEach(item => {
    const option = document.createElement("option");
    option.value = item.file;
    option.textContent = `${item.label} (${item.captured_at})`;
    select.appendChild(option);
  });

  if (!index.baselines.length) throw new Error("ベースラインがありません。");

  async function update() {
    const selected = index.baselines.find(item => item.file === select.value);
    const baseline = await loadJson(`${dataRoot}/${encodeURIComponent(select.value)}`);
    document.querySelector("#baseline-note").textContent = selected.note || "保存済み計画との比較";
    render(baseline, current);
  }

  select.addEventListener("change", update);
  document.querySelector("#snapshot-button").addEventListener("click", async () => {
    const button = document.querySelector("#snapshot-button");
    const message = document.querySelector("#snapshot-message");
    const label = document.querySelector("#snapshot-label").value.trim();
    const note = document.querySelector("#snapshot-note").value.trim();
    if (!label) {
      message.textContent = "名前を入力してください。";
      return;
    }
    button.disabled = true;
    message.textContent = "保存中...";
    try {
      current = await loadCurrentPlan();
      const response = await fetch("/baseline-api/snapshot", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-PJ-Baseline": "snapshot"
        },
        body: JSON.stringify({ project, label, note, payload: current })
      });
      if (!response.ok) throw new Error(`保存に失敗しました (${response.status})`);
      message.textContent = "スナップショットを保存しました。";
      window.setTimeout(() => window.location.reload(), 700);
    } catch (error) {
      message.textContent = error.message;
      button.disabled = false;
    }
  });
  await update();
}

main().catch(error => {
  document.querySelector("#comparison-body").innerHTML =
    `<tr><td colspan="7">比較データを読み込めませんでした: ${escapeHtml(error.message)}</td></tr>`;
});
