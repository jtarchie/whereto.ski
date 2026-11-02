import { el, show } from "./dom.js";
import { formatAll } from "./format.js";
import { loadIndex, snowLevel } from "./shared.js";

// Decoded index ({ entries, steps }); null until loaded, and stays null if the load failed.
let index = null;
let loading = null;
let ui = null;

export const searchIndex = () => index;

const GROUPS = [["c", "Countries"], ["s", "Regions"], ["r", "Resorts"]];

export function loadSearchData() {
  if (index) return Promise.resolve();
  loading ??= loadIndex()
    .then((decoded) => {
      index = decoded;
      show(ui.error, false);
    })
    .catch(() => show(ui.error, true))
    .finally(() => {
      loading = null;
      show(ui.loading, false);
      performSearch(ui.input.value);
    });
  show(ui.loading, true);
  return loading;
}

function resultItem(item, steps) {
  const link = el(
    "a",
    "flex items-center gap-3 rounded-md px-2 py-2 no-underline hover:bg-inset",
  );
  link.href = item.url;
  const text = el("span", "min-w-0 grow");
  text.append(el("span", "block truncate font-medium", item.name));
  const place = item.type === "r"
    ? [item.region, item.country]
    : [item.country];
  const meta = place.filter(Boolean).join(" · ");
  if (meta) {
    text.append(el("span", "block truncate text-xs text-ink-2", meta));
  }
  link.append(text);

  if (item.type === "r") {
    const level = snowLevel(item.snow, steps);
    const snow = el(
      "data",
      level
        ? `shrink-0 rounded-sm px-1.5 text-sm font-medium bg-snow-${level} text-on-snow-${level}`
        : "shrink-0 px-1.5 text-sm text-ink-3",
      "–",
    );
    snow.value = item.snow;
    if (level) snow.dataset.k = "s";
    snow.title = "Next 7 days";
    link.append(snow);
  }

  const li = el("li");
  li.append(link);
  return li;
}

// Name matches outrank region/country matches; within a rank, snowier resorts first.
function performSearch(query) {
  const q = query.toLowerCase().trim();
  ui.results.replaceChildren();
  show(ui.empty, false);
  if (!index || !q) return;

  const rank = (item) => {
    const name = item.name.toLowerCase();
    if (name.startsWith(q)) return 0;
    if (name.includes(q)) return 1;
    return [item.region, item.country].some((p) => p?.toLowerCase().includes(q))
      ? 2
      : -1;
  };
  const results = index.entries
    .map((item) => ({ item, rank: rank(item) }))
    .filter((r) => r.rank >= 0)
    .sort((a, b) => a.rank - b.rank || b.item.snow - a.item.snow)
    .slice(0, 50)
    .map((r) => r.item);

  if (results.length === 0) {
    show(ui.empty, true);
    return;
  }

  GROUPS.forEach(([type, label]) => {
    const items = results.filter((r) => r.type === type);
    if (!items.length) return;
    const section = el("section", "mb-4");
    section.append(
      el(
        "h3",
        "mb-1 px-2 text-xs font-medium tracking-wide text-ink-2 uppercase",
        label,
      ),
    );
    const list = el("ul");
    items.forEach((item) => list.append(resultItem(item, index.steps)));
    section.append(list);
    ui.results.append(section);
  });
  formatAll(ui.results);
}

// Debounce so we don't search on every keystroke.
function debounce(func, wait) {
  let timeout;
  executedFunction.cancel = () => clearTimeout(timeout);
  return executedFunction;
  function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  }
}

export function initSearch() {
  const modal = document.getElementById("search-modal");
  ui = {
    input: document.getElementById("search-input"),
    results: document.getElementById("search-results"),
    loading: document.getElementById("search-loading"),
    empty: document.getElementById("search-empty"),
    error: document.getElementById("search-error"),
  };
  const debouncedSearch = debounce(performSearch, 300);

  function openSearch() {
    if (modal.open) return;
    modal.showModal();
    ui.input.focus();
    loadSearchData();
  }

  document.getElementById("search-button").addEventListener(
    "click",
    openSearch,
  );

  if (window.visualViewport) {
    const modalBox = modal.querySelector(".dialog-box");
    if (modalBox) {
      window.visualViewport.addEventListener("resize", () => {
        if (modal.open) {
          modalBox.style.maxHeight =
            `${window.visualViewport.height - 20}px`;
        }
      });

      // Keep modal visible when the keyboard pushes content.
      window.visualViewport.addEventListener("scroll", () => {
        if (modal.open) {
          modalBox.style.transform =
            `translateY(${window.visualViewport.offsetTop}px)`;
        }
      });
    }
  }

  ui.input.addEventListener("input", (e) => debouncedSearch(e.target.value));

  modal.addEventListener("close", () => {
    debouncedSearch.cancel();
    ui.input.value = "";
    ui.results.replaceChildren();
    show(ui.empty, false);
    const modalBox = modal.querySelector(".dialog-box");
    if (modalBox) {
      modalBox.style.maxHeight = "";
      modalBox.style.transform = "";
    }
  });

  // Native <dialog> ignores backdrop clicks; the dialog element itself is the backdrop hit area.
  document.querySelectorAll("dialog").forEach((dialog) => {
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog) dialog.close();
    });
  });

  // Cmd/Ctrl+K anywhere; "/" only when the user isn't typing somewhere else.
  document.addEventListener("keydown", (e) => {
    const typing = e.target.closest?.(
      "input, textarea, select, [contenteditable]",
    );
    if (
      ((e.metaKey || e.ctrlKey) && e.key === "k") || (e.key === "/" && !typing)
    ) {
      e.preventDefault();
      openSearch();
    }
  });
}
