#include "utils/theme_inject.hpp"

namespace duckdb {
namespace ui {

namespace {

const char *kThemeMarker = "data-dd-ui-fork-theme=\"1\"";

const char *kThemeInject = R"HTML(
<style id="dd-ui-fork-theme-css">
  /* Fork-only theme — VS Code / DevTools Dark+ palette */
  :root {
    --dd-ui-bg: #1e1e1e;
    --dd-ui-bg-elevated: #252526;
    --dd-ui-bg-highlight: #2a2d2e;
    --dd-ui-fg: #d4d4d4;
    --dd-ui-fg-muted: #858585;
    --dd-ui-tag: #569cd6;
    --dd-ui-attr: #9cdcfe;
    --dd-ui-string: #ce9178;
    --dd-ui-comment: #6a9955;
    --dd-ui-selection: #264f78;
    --dd-ui-accent: #569cd6;
  }
  .dd-ui-fork-theme-row {
    display: inline-flex !important;
    flex-direction: row !important;
    flex-wrap: nowrap !important;
    align-items: center !important;
    gap: 8px;
  }
  #dd-ui-fork-theme-btn {
    box-sizing: border-box;
    width: 24px;
    height: 24px;
    margin: 0;
    padding: 0;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: inherit;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: 0 0 24px;
    opacity: 0.85;
  }
  #dd-ui-fork-theme-btn:hover {
    opacity: 1;
    background: rgba(86, 156, 214, 0.18);
  }
  #dd-ui-fork-theme-btn:focus-visible {
    outline: 2px solid var(--dd-ui-accent);
    outline-offset: 1px;
  }
  #dd-ui-fork-theme-btn svg {
    width: 16px;
    height: 16px;
    display: block;
    stroke: currentColor;
  }
  html[data-dd-ui-theme="dark"] {
    color-scheme: dark;
    background-color: var(--dd-ui-bg);
  }
  html[data-dd-ui-theme="dark"] body {
    background-color: var(--dd-ui-bg) !important;
    color: var(--dd-ui-fg);
  }
  html[data-dd-ui-theme="dark"] ::selection {
    background: var(--dd-ui-selection);
    color: var(--dd-ui-fg);
  }
  /*
   * Real dark theme: remap shell tokens on .t0ok310 (see local CSS).
   * Do not use invert — it collapses to pure black and skips Dark+.
   */
  html[data-dd-ui-theme="dark"] #dd-ui-fork-theme-btn {
    color: #569cd6;
    background: rgba(86, 156, 214, 0.22);
    opacity: 1;
  }
  html[data-dd-ui-theme="dark"] #app {
    filter: none;
    background-color: transparent;
  }
  html[data-dd-ui-theme="dark"] *::-webkit-scrollbar {
    width: 10px;
    height: 10px;
  }
  html[data-dd-ui-theme="dark"] *::-webkit-scrollbar-track {
    background: var(--dd-ui-bg);
  }
  html[data-dd-ui-theme="dark"] *::-webkit-scrollbar-thumb {
    background: #424242;
    border-radius: 4px;
  }
  html[data-dd-ui-theme="dark"] *::-webkit-scrollbar-thumb:hover {
    background: #4f4f4f;
  }
</style>
<!-- Optional local overlays from ui_assets_path (start_ui / dev_theme sync these). -->
<link rel="stylesheet" href="/dd-ui-fork-theme-local.css?v=darkplus-tokens" />
<script src="/dd-ui-fork-overlays.js?v=path-i18n" defer></script>
<script id="dd-ui-fork-theme-js">
(function () {
  if (window.__DUCKDB_UI_FORK_THEME__) return;
  window.__DUCKDB_UI_FORK_THEME__ = true;

  var STORAGE_KEY = "duckdb-ui-fork-theme";
  var ATTR = "data-dd-ui-theme";
  var BTN_ID = "dd-ui-fork-theme-btn";

  function preferred() {
    try {
      var saved = localStorage.getItem(STORAGE_KEY);
      if (saved === "dark" || saved === "light") return saved;
    } catch (e) {}
    if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
      return "dark";
    }
    return "light";
  }

  function apply(theme) {
    document.documentElement.setAttribute(ATTR, theme);
    try { localStorage.setItem(STORAGE_KEY, theme); } catch (e) {}
    var btn = document.getElementById(BTN_ID);
    if (btn) {
      var dark = theme === "dark";
      btn.setAttribute("aria-label", dark ? "切换到浅色主题" : "切换到深色主题");
      btn.setAttribute("title", dark ? "浅色主题" : "深色主题");
      btn.innerHTML = dark
        ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
        : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 14.5A8.5 8.5 0 1 1 9.5 3a7 7 0 0 0 11.5 11.5z"/></svg>';
    }
  }

  function toggle() {
    var cur = document.documentElement.getAttribute(ATTR) || preferred();
    apply(cur === "dark" ? "light" : "dark");
  }

  // Inspector sits inside a Radix tooltip trigger (narrow div[data-state]).
  // Insert beside that wrapper in the toolbar row — not inside it (which stacks vertically).
  function resolveInsertPoint(inspector) {
    var anchor = inspector;
    var host = inspector.parentElement;
    if (!host) return null;
    if (host.hasAttribute("data-state") || host.getAttribute("role") === "button") {
      anchor = host;
      host = host.parentElement;
    }
    if (!host) return null;
    return { host: host, anchor: anchor };
  }

  function placeButton() {
    if (document.getElementById(BTN_ID)) return true;
    var inspector = document.querySelector('[data-testid="inspector-drawer-button"]');
    if (!inspector) return false;
    var point = resolveInsertPoint(inspector);
    if (!point) return false;
    var btn = document.createElement("button");
    btn.id = BTN_ID;
    btn.type = "button";
    btn.setAttribute("data-testid", "duckdb-ui-fork-theme-button");
    btn.addEventListener("click", function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      toggle();
    });
    point.host.classList.add("dd-ui-fork-theme-row");
    point.host.insertBefore(btn, point.anchor);
    apply(preferred());
    return true;
  }

  apply(preferred());

  if (!placeButton()) {
    var obs = new MutationObserver(function () {
      if (placeButton()) obs.disconnect();
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(function () { try { obs.disconnect(); } catch (e) {} }, 30000);
  }
})();
</script>
)HTML";

} // namespace

void InjectForkThemeToggle(std::string &html_body) {
	if (html_body.find(kThemeMarker) != std::string::npos) {
		return;
	}
	// Only touch HTML documents.
	const auto head_close = html_body.find("</head>");
	const auto head_close_upper = html_body.find("</HEAD>");
	size_t pos = std::string::npos;
	if (head_close != std::string::npos) {
		pos = head_close;
	} else if (head_close_upper != std::string::npos) {
		pos = head_close_upper;
	}
	std::string snippet = std::string("<!-- ") + kThemeMarker + " -->\n"
	                      "<script>(function(){try{var t=localStorage.getItem('duckdb-ui-fork-theme');"
	                      "if(t==='dark'||t==='light')document.documentElement.setAttribute('data-dd-ui-theme',t);"
	                      "else if(window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches)"
	                      "document.documentElement.setAttribute('data-dd-ui-theme','dark');"
	                      "}catch(e){}})();</script>\n" +
	                      kThemeInject + "\n";
	if (pos != std::string::npos) {
		html_body.insert(pos, snippet);
		return;
	}
	const auto body_close = html_body.find("</body>");
	const auto body_close_upper = html_body.find("</BODY>");
	if (body_close != std::string::npos) {
		html_body.insert(body_close, snippet);
	} else if (body_close_upper != std::string::npos) {
		html_body.insert(body_close_upper, snippet);
	} else {
		html_body.append(snippet);
	}
}

} // namespace ui
} // namespace duckdb
