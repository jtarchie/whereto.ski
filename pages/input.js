(function () {
  const $units = document.getElementById("unit-toggle");
  const $tz = document.getElementById("tz-select");

  // Raw values are imperial (see lib/follow_the_snow/builder/units.rb).
  const KINDS = {
    s: (v, m) => (m ? [v * 2.54, " cm"] : [v, "″"]),
    t: (v, m) => (m ? [((v - 32) * 5) / 9, "°C"] : [v, "°F"]),
    w: (v, m) => (m ? [v * 1.60934, " km/h"] : [v, " mph"]),
    h: (v, m) => (m ? [v * 0.3048, " m"] : [v, " ft"]),
    d: (v, m) => (m ? [v, " km"] : [v * 0.621371, " mi"]),
  };
  const numberFormats = [0, 1].map((digits) =>
    new Intl.NumberFormat(undefined, { maximumFractionDigits: digits })
  );

  const isMetric = () => {
    const saved = localStorage.getItem("preferredUnits");
    return saved ? saved === "metric" : navigator.language !== "en-US";
  };

  const resortZone = () =>
    document.querySelector("[data-resort-tz]")?.dataset.resortTz;

  function timeZone() {
    const pref = localStorage.getItem("preferredTimezone") || "auto";
    const zone = pref === "auto"
      ? undefined
      : pref === "resort"
      ? resortZone()
      : pref;
    try {
      new Intl.DateTimeFormat(undefined, { timeZone: zone });
      return zone;
    } catch {
      return undefined;
    }
  }

  function formatAll(root = document) {
    const metric = isMetric();
    root.querySelectorAll("data[data-k]").forEach((el) => {
      const convert = KINDS[el.dataset.k];
      if (!convert) return;
      const [n, unit] = convert(parseFloat(el.value), metric);
      const digits = el.dataset.k === "s" && Math.abs(n) < 10 ? 1 : 0;
      el.textContent = numberFormats[digits].format(n) + unit;
    });

    const zone = timeZone();
    const hour = new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      timeZone: zone,
    });
    const dayHour = new Intl.DateTimeFormat(undefined, {
      weekday: "short",
      hour: "numeric",
      timeZone: zone,
    });
    const full = new Intl.DateTimeFormat(undefined, {
      weekday: "short",
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
      timeZone: zone,
    });
    document.querySelectorAll("time[data-k]").forEach((el) => {
      const date = new Date(el.dateTime);
      const format = { hr: hour, dh: dayHour }[el.dataset.k] ?? full;
      el.textContent = format.format(date);
    });

    const name = new Intl.DateTimeFormat(undefined, {
      timeZoneName: "short",
      timeZone: zone,
    }).formatToParts(new Date()).find((p) => p.type === "timeZoneName");
    document.querySelectorAll("[data-tz-label]").forEach((el) => {
      el.textContent = name?.value ?? "";
    });
  }

  function initTimezoneSelect() {
    const detected = Intl.DateTimeFormat().resolvedOptions().timeZone;
    $tz.options[0].textContent = `Auto (${detected})`;
    if (!resortZone()) {
      $tz.options[1].textContent = "Resort local (on resort pages)";
    }
    (Intl.supportedValuesOf?.("timeZone") ?? []).forEach((zone) => {
      $tz.add(new Option(zone.replaceAll("_", " "), zone));
    });
    $tz.value = localStorage.getItem("preferredTimezone") || "auto";
    if (!$tz.value) $tz.value = "auto";
  }

  $units.addEventListener("change", () => {
    localStorage.setItem(
      "preferredUnits",
      $units.checked ? "metric" : "imperial",
    );
    formatAll();
  });

  $tz.addEventListener("change", () => {
    localStorage.setItem("preferredTimezone", $tz.value);
    formatAll();
  });

  window.addEventListener("DOMContentLoaded", () => {
    $units.checked = isMetric();
    initTimezoneSelect();
    formatAll();

    // Snow filter toggle functionality
    const filterSnowToggle = document.getElementById("filter-snow-toggle");
    if (filterSnowToggle) {
      // Load saved filter preference
      const filterSnowOnly = localStorage.getItem("filterSnowOnly") === "true";
      filterSnowToggle.checked = filterSnowOnly;
      if (filterSnowOnly) {
        document.body.classList.add("filter-snow-only");
      }

      // Handle toggle changes
      filterSnowToggle.addEventListener("change", () => {
        const isChecked = filterSnowToggle.checked;
        if (isChecked) {
          document.body.classList.add("filter-snow-only");
        } else {
          document.body.classList.remove("filter-snow-only");
        }
        localStorage.setItem("filterSnowOnly", isChecked);
      });
    }

    initRankedLists();
  });

  // Ranked lists: server order is the 7d default; any other key sorts descending, tapping it again restores.
  function initRankedLists() {
    const table = document.querySelector("[data-ranked]");
    if (!table) return;
    const body = table.tBodies[0];
    const original = [...body.rows];
    const value = (row, key) =>
      parseFloat(
        (/^\d{4}-/.test(key)
          ? [...row.querySelectorAll(".strip i")].find((i) =>
            i.style.gridColumnStart === dayColumn(key)
          )?.dataset.v
          : row.querySelector(`td[data-s="${key}"] data`)?.value) ?? 0,
      ) || 0;
    const dayButtons = [...table.querySelectorAll(".days button")];
    const dayColumn = (key) =>
      String(dayButtons.findIndex((b) => b.dataset.sort === key) + 1);
    let current = "7d";

    function apply(key) {
      const rows = key === "7d"
        ? original
        : [...original].sort((a, b) => value(b, key) - value(a, key));
      rows.forEach((row, index) => {
        row.cells[0].textContent = index + 1;
        body.appendChild(row);
      });
      const isDay = /^\d{4}-/.test(key);
      table.querySelectorAll("thead th[data-s]").forEach((th) => {
        const active = th.dataset.s === (isDay ? "day" : key);
        active
          ? th.setAttribute("aria-sort", "descending")
          : th.setAttribute("aria-sort", "none");
      });
      table.querySelectorAll(".days button").forEach((button) =>
        button.setAttribute("aria-pressed", button.dataset.sort === key)
      );
      current = key;
      const url = new URL(location.href);
      key === "7d"
        ? url.searchParams.delete("sort")
        : url.searchParams.set("sort", key);
      history.replaceState(null, "", url);
    }

    table.querySelectorAll("thead button[data-sort]").forEach((button) => {
      button.addEventListener(
        "click",
        () =>
          apply(button.dataset.sort === current ? "7d" : button.dataset.sort),
      );
    });

    const requested = new URLSearchParams(location.search).get("sort");
    if (requested && table.querySelector(`button[data-sort="${requested}"]`)) {
      apply(requested);
    }
  }

  let searchData = null;
  let loading = null;

  const modal = document.getElementById("search-modal");
  const searchButton = document.getElementById("search-button");
  const searchInput = document.getElementById("search-input");
  const searchResults = document.getElementById("search-results");
  const searchLoading = document.getElementById("search-loading");
  const searchEmpty = document.getElementById("search-empty");
  const searchError = document.getElementById("search-error");

  const show = (el, visible) => el.classList.toggle("hidden", !visible);

  // Index format: { cl: [countries], d: [{t, n, c, s, u, l, w}] }; t = c/s/r, c = index into cl, l = [lat, lon], w = 7-day snow (omitted when 0).
  function loadSearchData() {
    if (searchData) return Promise.resolve();
    loading ??= fetch("/assets/search-data.json")
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.json();
      })
      .then((raw) => {
        searchData = raw.d.map((item) => ({
          type: item.t,
          name: item.n,
          country: typeof item.c === "number" ? raw.cl[item.c] : undefined,
          region: item.s,
          url: item.u,
          snow: item.w ?? 0,
        }));
        show(searchError, false);
      })
      .catch(() => show(searchError, true))
      .finally(() => {
        loading = null;
        show(searchLoading, false);
        performSearch(searchInput.value);
      });
    show(searchLoading, true);
    return loading;
  }

  const SNOW_STEPS = [1, 2, 6, 12];
  const snowLevel = (inches) =>
    inches <= 0 ? 0 : SNOW_STEPS.filter((step) => inches >= step).length + 1;

  const GROUPS = [["c", "Countries"], ["s", "Regions"], ["r", "Resorts"]];

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function resultItem(item) {
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
      const level = snowLevel(item.snow);
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
    searchResults.replaceChildren();
    show(searchEmpty, false);
    if (!searchData || !q) return;

    const rank = (item) => {
      const name = item.name.toLowerCase();
      if (name.startsWith(q)) return 0;
      if (name.includes(q)) return 1;
      return [item.region, item.country].some((p) =>
          p?.toLowerCase().includes(q)
        )
        ? 2
        : -1;
    };
    const results = searchData
      .map((item) => ({ item, rank: rank(item) }))
      .filter((r) => r.rank >= 0)
      .sort((a, b) => a.rank - b.rank || b.item.snow - a.item.snow)
      .slice(0, 50)
      .map((r) => r.item);

    if (results.length === 0) {
      show(searchEmpty, true);
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
      items.forEach((item) => list.append(resultItem(item)));
      section.append(list);
      searchResults.append(section);
    });
    formatAll(searchResults);
  }

  // Debounce function to avoid searching on every keystroke
  function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  }

  const debouncedSearch = debounce(performSearch, 300);

  function openSearch() {
    if (modal.open) return;
    modal.showModal();
    searchInput.focus();
    loadSearchData();
  }

  searchButton.addEventListener("click", openSearch);

  // Handle virtual keyboard on mobile
  function handleMobileKeyboard() {
    if (!window.visualViewport) return;

    const modalBox = modal.querySelector(".dialog-box");
    if (!modalBox) return;

    window.visualViewport.addEventListener("resize", () => {
      if (modal.open) {
        // Adjust modal height based on visible viewport
        const viewportHeight = window.visualViewport.height;
        modalBox.style.maxHeight = `${viewportHeight - 20}px`;
      }
    });

    window.visualViewport.addEventListener("scroll", () => {
      if (modal.open) {
        // Keep modal visible when keyboard pushes content
        modalBox.style.transform =
          `translateY(${window.visualViewport.offsetTop}px)`;
      }
    });
  }

  // Initialize mobile keyboard handling
  handleMobileKeyboard();

  // Search on input
  searchInput.addEventListener("input", (e) => {
    debouncedSearch(e.target.value);
  });

  // Reset modal styles when closed
  modal.addEventListener("close", () => {
    searchInput.value = "";
    searchResults.replaceChildren();
    show(searchEmpty, false);
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
})();
