(() => {
  if (!window.location.pathname.includes("/projects/")) return;

  const project = window.location.pathname.split("/projects/")[1]?.split("/")[0];
  if (!project) return;

  const reportUrl = `/baseline/?project=${encodeURIComponent(project)}`;

  const style = document.createElement("style");
  style.textContent = `
    .pj-baseline-replacement {
      cursor: pointer;
    }
  `;
  document.head.appendChild(style);

  const isBaselineButton = element => {
    const text = element.textContent?.trim() || "";
    const attributes = [
      element.getAttribute("aria-label"),
      element.getAttribute("title"),
      element.getAttribute("data-test-selector")
    ].filter(Boolean).join(" ");

    return /ベースライン|baseline/i.test(`${text} ${attributes}`);
  };

  const replaceBaselineButton = () => {
    const candidates = document.querySelectorAll("button, a");
    for (const element of candidates) {
      if (!isBaselineButton(element)) continue;
      if (element.classList.contains("pj-baseline-replacement")) return;

      element.classList.add("pj-baseline-replacement");
      element.setAttribute("aria-label", "計画比較");
      element.setAttribute("title", "保存したベースラインと現在計画を比較");
      element.removeAttribute("aria-haspopup");
      element.removeAttribute("aria-expanded");
      element.removeAttribute("popovertarget");

      const textNodes = [...element.querySelectorAll("span")].filter(node =>
        /ベースライン|baseline/i.test(node.textContent || "")
      );
      if (textNodes.length) {
        textNodes[textNodes.length - 1].textContent = "計画比較";
      } else {
        element.textContent = "計画比較";
      }

      element.addEventListener("click", event => {
        event.preventDefault();
        event.stopImmediatePropagation();
        window.location.assign(reportUrl);
      }, true);
      return;
    }
  };

  replaceBaselineButton();
  new MutationObserver(replaceBaselineButton).observe(document.body, {
    childList: true,
    subtree: true
  });
})();
