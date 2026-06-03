(() => {
  const isProjectPage = window.location.pathname.includes("/projects/");
  const isGanttPage = window.location.pathname.includes("/gantt");
  if (!isProjectPage && !isGanttPage) return;

  const project = isProjectPage
    ? window.location.pathname.split("/projects/")[1]?.split("/")[0]
    : null;

  const reportUrl = project
    ? `/baseline/?project=${encodeURIComponent(project)}`
    : "/baseline/";
  const buttonId = "pj-plan-compare-button";

  const style = document.createElement("style");
  style.textContent = `
    .pj-hidden-baseline-button {
      display: none !important;
    }
    .pj-plan-compare-button {
      cursor: pointer;
    }
    .pj-plan-compare-floating {
      position: fixed;
      top: 72px;
      right: 24px;
      z-index: 1000;
      padding: 7px 12px;
      border: 1px solid #0969da;
      border-radius: 6px;
      color: #fff;
      background: #0969da;
      font-weight: 700;
      box-shadow: 0 4px 12px rgb(15 23 42 / 16%);
    }
  `;
  document.head.appendChild(style);

  const buttonText = "計画比較";
  const titleText = "保存したベースラインと現在計画を比較";

  const isBaselineButton = element => {
    const text = element.textContent?.trim() || "";
    const attributes = [
      element.getAttribute("aria-label"),
      element.getAttribute("title"),
      element.getAttribute("data-test-selector")
    ].filter(Boolean).join(" ");

    return /ベースライン|baseline/i.test(`${text} ${attributes}`);
  };

  const wireButton = button => {
    button.id = buttonId;
    button.classList.add("pj-plan-compare-button");
    button.setAttribute("aria-label", buttonText);
    button.setAttribute("title", titleText);
    button.addEventListener("click", event => {
      event.preventDefault();
      event.stopImmediatePropagation();
      window.location.assign(reportUrl);
    }, true);
  };

  const setButtonText = button => {
    const label = button.querySelector(".Button-label, span");
    if (label) {
      label.textContent = buttonText;
    } else {
      button.textContent = buttonText;
    }
  };

  const createButtonFrom = baselineButton => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = baselineButton?.className || "Button Button--medium";
    if (!button.className.includes("Button")) {
      button.className += " Button Button--medium";
    }
    button.innerHTML = `<span class="Button-content"><span class="Button-label">${buttonText}</span></span>`;
    wireButton(button);
    return button;
  };

  const findToolbar = () => document.querySelector(
    ".toolbar-container, .toolbar-items, .op-toolbar, [data-test-selector*='toolbar'], main"
  );

  const ensurePlanCompareButton = () => {
    if (document.getElementById(buttonId)) return;

    const baselineButton = [...document.querySelectorAll("button, a")].find(isBaselineButton);
    if (baselineButton) {
      const button = createButtonFrom(baselineButton);
      baselineButton.classList.add("pj-hidden-baseline-button");
      baselineButton.insertAdjacentElement("beforebegin", button);
      return;
    }

    if (!window.location.pathname.includes("/gantt")) return;

    const toolbar = findToolbar();
    if (!toolbar) return;

    const button = document.createElement("button");
    button.type = "button";
    button.className = "pj-plan-compare-floating";
    button.textContent = buttonText;
    wireButton(button);
    toolbar.appendChild(button);
  };

  const hideBaselineButtons = () => {
    [...document.querySelectorAll("button, a")]
      .filter(isBaselineButton)
      .forEach(element => element.classList.add("pj-hidden-baseline-button"));
  };

  const refresh = () => {
    ensurePlanCompareButton();
    hideBaselineButtons();
    const button = document.getElementById(buttonId);
    if (button) setButtonText(button);
  };

  refresh();
  new MutationObserver(refresh).observe(document.body, {
    childList: true,
    subtree: true
  });
})();
