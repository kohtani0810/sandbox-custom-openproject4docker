(() => {
  const path = window.location.pathname;
  const isProjectPage = path.includes("/projects/");
  const isGanttPage = path.includes("/gantt");
  const isWorkPackagesPage = path.includes("/work_packages");
  const canCreateBaseline = isGanttPage || isWorkPackagesPage;
  if (!isProjectPage && !canCreateBaseline) return;

  const project = isProjectPage ? path.split("/projects/")[1]?.split("/")[0] : "all-projects";
  const reportUrl = project ? `/baseline/?project=${encodeURIComponent(project)}` : "/baseline/";
  const baselineButtonSelector = '[data-test-selector="baseline-button"]';
  const snapshotButtonId = "pj-baseline-snapshot-button";
  const buttonText = "計画比較";
  let creatingSnapshot = false;

  const style = document.createElement("style");
  style.textContent = `
    .pj-baseline-message {
      position: fixed;
      top: 84px;
      right: 24px;
      z-index: 10000;
      max-width: 440px;
      padding: 12px 16px;
      border: 1px solid #86efac;
      border-radius: 8px;
      color: #14532d;
      background: #dcfce7;
      box-shadow: 0 8px 24px rgb(15 23 42 / 18%);
      font: 700 14px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .pj-baseline-message.error {
      border-color: #fca5a5;
      color: #7f1d1d;
      background: #fee2e2;
    }
    #${snapshotButtonId} {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      min-height: 34px;
      margin-right: 8px;
      padding: 0 12px;
      border: 1px solid #cbd5e1;
      border-radius: 4px;
      color: #0f172a;
      background: #fff;
      font: 600 14px/1.2 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      cursor: pointer;
      white-space: nowrap;
    }
    #${snapshotButtonId}:hover {
      border-color: #94a3b8;
      background: #f8fafc;
    }
    #${snapshotButtonId}[aria-busy="true"] {
      cursor: progress;
      opacity: 0.72;
    }
  `;
  document.head.appendChild(style);

  const textOf = value => String(value ?? "").replace(/\s+/g, " ").trim();

  const showMessage = (text, isError = false) => {
    document.querySelector(".pj-baseline-message")?.remove();
    const message = document.createElement("div");
    message.className = `pj-baseline-message${isError ? " error" : ""}`;
    message.setAttribute("role", "status");
    message.textContent = text;
    document.body.appendChild(message);
    window.setTimeout(() => message.remove(), isError ? 8000 : 5000);
  };

  const durationToHours = duration => {
    if (duration === null || duration === undefined || duration === "") return null;
    if (typeof duration === "number") return duration;
    const match = String(duration).match(/^P(?:(\d+(?:\.\d+)?)D)?T?(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$/);
    if (!match) return null;
    return Number(match[1] || 0) * 24 + Number(match[2] || 0) + Number(match[3] || 0) / 60 + Number(match[4] || 0) / 3600;
  };

  const projectName = () => {
    const title = document.querySelector("h1")?.textContent;
    if (project === "all-projects") return "全プロジェクト";
    return textOf(title) || project;
  };

  const loadCurrentPlan = async () => {
    const url = project === "all-projects"
      ? "/api/v3/work_packages?pageSize=1000"
      : `/api/v3/projects/${encodeURIComponent(project)}/work_packages?pageSize=1000`;
    const response = await fetch(url, {
      credentials: "same-origin",
      headers: { Accept: "application/hal+json" }
    });
    if (!response.ok) throw new Error(`現在計画を取得できませんでした (${response.status})`);
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
      project_name: projectName(),
      captured_at: new Date().toISOString(),
      total_estimated_hours: workPackages.reduce((sum, item) => sum + Number(item.estimated_hours || 0), 0),
      work_packages: workPackages
    };
  };

  const createSnapshot = async source => {
    if (creatingSnapshot) return;
    creatingSnapshot = true;
    source?.setAttribute?.("aria-busy", "true");
    source?.setAttribute?.("disabled", "disabled");
    showMessage("ベースラインを作成しています...");
    try {
      const now = new Date();
      const payload = await loadCurrentPlan();
      const label = `作成ボタン ${now.toLocaleString("ja-JP")}`;
      const response = await fetch("/baseline-api/snapshot", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-PJ-Baseline": "snapshot"
        },
        body: JSON.stringify({
          project,
          label,
          note: "ガントチャートのベースライン作成ボタンから作成",
          payload
        })
      });
      if (!response.ok) {
        const error = await response.json().catch(() => ({}));
        throw new Error(error.error || `ベースライン作成に失敗しました (${response.status})`);
      }
      showMessage("ベースラインを作成しました。計画比較画面で選択できます。成功しました。");
    } catch (error) {
      showMessage(error.message || "ベースライン作成に失敗しました。", true);
    } finally {
      creatingSnapshot = false;
      source?.removeAttribute?.("aria-busy");
      source?.removeAttribute?.("disabled");
    }
  };

  const updateBaselineButtonText = () => {
    document.querySelectorAll(baselineButtonSelector).forEach(button => {
      button.setAttribute("aria-label", buttonText);
      button.setAttribute("title", "保存した計画と現在計画を比較");

      const label = button.querySelector(".button--text");
      if (label) label.textContent = buttonText;
    });
  };

  const isCreateButton = element => {
    if (!canCreateBaseline || !element?.matches?.("button, a")) return false;
    if (element.id === snapshotButtonId || element.closest(baselineButtonSelector)) return false;
    const values = [
      textOf(element.textContent),
      textOf(element.getAttribute("aria-label")),
      textOf(element.getAttribute("title"))
    ];
    return values.some(value => /^\+?\s*作成\s*$/.test(value) || value === "新規作成");
  };

  const findCreateButton = () => [...document.querySelectorAll("button, a")].find(isCreateButton);

  const addSnapshotButton = () => {
    if (!canCreateBaseline || document.getElementById(snapshotButtonId)) return;
    const createButton = findCreateButton();
    if (!createButton?.parentElement) return;

    const button = document.createElement("button");
    button.id = snapshotButtonId;
    button.type = "button";
    button.textContent = "ベースライン作成";
    button.title = "現在の計画をベースラインとして作成";
    button.setAttribute("aria-label", "ベースラインを作成");
    button.addEventListener("click", event => {
      event.preventDefault();
      event.stopPropagation();
      createSnapshot(button);
    });

    createButton.insertAdjacentElement("beforebegin", button);
  };

  document.addEventListener(
    "click",
    event => {
      const button = event.target.closest?.(baselineButtonSelector);
      if (!button) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      window.location.assign(reportUrl);
    },
    true
  );

  const refresh = () => {
    updateBaselineButtonText();
    addSnapshotButton();
    [300, 1000, 2500, 5000].forEach(delay => window.setTimeout(() => {
      updateBaselineButtonText();
      addSnapshotButton();
    }, delay));
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", refresh, { once: true });
  } else {
    refresh();
  }
})();
