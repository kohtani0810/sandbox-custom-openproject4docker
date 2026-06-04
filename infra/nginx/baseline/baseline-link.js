(() => {
  const path = window.location.pathname;
  const isProjectPage = path.includes("/projects/");
  const isGanttPage = path.includes("/gantt");
  if (!isProjectPage && !isGanttPage) return;

  const project = isProjectPage ? path.split("/projects/")[1]?.split("/")[0] : null;
  const reportUrl = project ? `/baseline/?project=${encodeURIComponent(project)}` : "/baseline/";
  const selector = '[data-test-selector="baseline-button"]';
  const buttonText = "計画比較";

  const updateButtonText = () => {
    document.querySelectorAll(selector).forEach(button => {
      button.setAttribute("aria-label", buttonText);
      button.setAttribute("title", "保存した計画と現在計画を比較");

      const label = button.querySelector(".button--text");
      if (label) label.textContent = buttonText;
    });
  };

  document.addEventListener(
    "click",
    event => {
      const button = event.target.closest?.(selector);
      if (!button) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      window.location.assign(reportUrl);
    },
    true
  );

  const refresh = () => {
    updateButtonText();
    [300, 1000, 2500, 5000].forEach(delay => window.setTimeout(updateButtonText, delay));
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", refresh, { once: true });
  } else {
    refresh();
  }
})();
