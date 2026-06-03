(() => {
  const path = window.location.pathname;
  const isProjectPage = path.includes("/projects/");
  const isGanttPage = path.includes("/gantt");
  if (!isProjectPage && !isGanttPage) return;

  const project = isProjectPage ? path.split("/projects/")[1]?.split("/")[0] : null;
  const reportUrl = project ? `/baseline/?project=${encodeURIComponent(project)}` : "/baseline/";
  const buttonId = "pj-plan-compare-button";
  const hiddenClass = "pj-hidden-baseline-button";
  const buttonText = "計画比較";

  const style = document.createElement("style");
  style.textContent = `
    .${hiddenClass} {
      display: none !important;
    }
    #${buttonId} {
      position: fixed;
      top: 176px;
      right: 84px;
      z-index: 9999;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      min-height: 34px;
      padding: 7px 13px;
      border: 1px solid #0969da;
      border-radius: 6px;
      color: #fff;
      background: #0969da;
      font: 700 14px/1.2 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      text-decoration: none;
      box-shadow: 0 4px 12px rgb(15 23 42 / 16%);
    }
    #${buttonId}:hover {
      background: #0757b8;
      color: #fff;
      text-decoration: none;
    }
    #${buttonId}::before {
      content: "⇄";
      font-size: 15px;
      line-height: 1;
    }
  `;
  document.head.appendChild(style);

  const isBaselineButton = element => {
    if (!element || element.id === buttonId) return false;
    const text = element.textContent?.trim() || "";
    const attributes = [
      element.getAttribute("aria-label"),
      element.getAttribute("title"),
      element.getAttribute("data-test-selector")
    ].filter(Boolean).join(" ");

    return /ベースライン|baseline/i.test(`${text} ${attributes}`);
  };

  const addPlanCompareButton = () => {
    if (document.getElementById(buttonId)) return;

    const button = document.createElement("a");
    button.id = buttonId;
    button.href = reportUrl;
    button.textContent = buttonText;
    button.setAttribute("aria-label", buttonText);
    button.setAttribute("title", "保存した計画と現在計画を比較");
    document.body.appendChild(button);
  };

  const hideBaselineButtons = () => {
    document.querySelectorAll("button, a").forEach(element => {
      if (isBaselineButton(element)) element.classList.add(hiddenClass);
    });
  };

  const refresh = () => {
    addPlanCompareButton();
    hideBaselineButtons();
  };

  const runLightweightRefreshes = () => {
    refresh();
    [300, 1000, 2500, 5000].forEach(delay => window.setTimeout(refresh, delay));
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", runLightweightRefreshes, { once: true });
  } else {
    runLightweightRefreshes();
  }
})();
