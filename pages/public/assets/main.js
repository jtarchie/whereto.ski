(function () {
  var $toggle = document.getElementById("unit-toggle");

  function toggleUnits() {
    var selected = $toggle.checked;
    if (selected) {
      document.body.classList.add("metric");
    } else {
      document.body.classList.remove("metric");
    }
  }

  $toggle.addEventListener("change", () => {
    toggleUnits();
    localStorage.setItem(
      "preferredUnits",
      $toggle.checked ? "metric" : "imperial"
    );
  });

  window.addEventListener("DOMContentLoaded", (event) => {
    const userLang = navigator.language || navigator.userLanguage;
    const preferredUnits = localStorage.getItem("preferredUnits");

    if (preferredUnits) {
      console.log("preferred units", preferredUnits);
      $toggle.checked = preferredUnits === "metric";
    } else if (userLang === "en-US") {
      $toggle.checked = false;
    } else {
      $toggle.checked = true;
    }

    toggleUnits();

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
  });
  let searchData = null;
  let isLoading = false;

  const modal = document.getElementById("search-modal");
  const searchButton = document.getElementById("search-button");
  const searchInput = document.getElementById("search-input");
  const searchResults = document.getElementById("search-results");
  const searchLoading = document.getElementById("search-loading");
  const searchEmpty = document.getElementById("search-empty");

  // Load search data lazily
  async function loadSearchData() {
    if (searchData || isLoading) return;

    isLoading = true;
    searchLoading.classList.remove("hidden");

    try {
      const response = await fetch("/assets/search-data.json");
      const rawData = await response.json();

      // Expand compressed format for easier searching
      // Format: { cl: [countries], d: [{t,n,c,s,u},...] }
      // t=type (c/s/r), n=name, c=country index, s=state, u=url
      searchData = rawData.d.map((item) => ({
        type: item.t === "c" ? "country" : item.t === "s" ? "state" : "resort",
        name: item.n,
        country: typeof item.c === "number" ? rawData.cl[item.c] : undefined,
        state: item.s,
        url: item.u,
      }));
    } catch (error) {
      console.error("Failed to load search data:", error);
      searchData = [];
    } finally {
      isLoading = false;
      searchLoading.classList.add("hidden");
    }
  }

  // Filter and display results
  function performSearch(query) {
    if (!searchData) return;

    const lowerQuery = query.toLowerCase().trim();

    if (!lowerQuery) {
      searchResults.innerHTML = "";
      searchEmpty.classList.add("hidden");
      return;
    }

    // Simple fuzzy search: matches if query appears anywhere in name, country, or state
    const results = searchData
      .filter((item) => {
        const nameMatch = item.name.toLowerCase().includes(lowerQuery);
        const countryMatch =
          item.country && item.country.toLowerCase().includes(lowerQuery);
        const stateMatch =
          item.state && item.state.toLowerCase().includes(lowerQuery);
        return nameMatch || countryMatch || stateMatch;
      })
      .slice(0, 50); // Limit to 50 results

    if (results.length === 0) {
      searchResults.innerHTML = "";
      searchEmpty.classList.remove("hidden");
      return;
    }

    searchEmpty.classList.add("hidden");

    // Group results by type for better UX
    const grouped = {
      country: results.filter((r) => r.type === "country"),
      state: results.filter((r) => r.type === "state"),
      resort: results.filter((r) => r.type === "resort"),
    };

    let html = "";

    // Render countries
    if (grouped.country.length > 0) {
      html +=
        '<div class="mb-4"><h4 class="font-semibold text-sm mb-2 text-base-content/60">Countries</h4><ul class="menu">';
      grouped.country.forEach((item) => {
        html += `<li><a href="${item.url}" class="flex items-center gap-2"><span>🌍</span><span>${item.name}</span></a></li>`;
      });
      html += "</ul></div>";
    }

    // Render states
    if (grouped.state.length > 0) {
      html +=
        '<div class="mb-4"><h4 class="font-semibold text-sm mb-2 text-base-content/60">States / Regions</h4><ul class="menu">';
      grouped.state.forEach((item) => {
        html += `<li><a href="${item.url}" class="flex items-center gap-2"><span>📍</span><span>${item.name}</span><span class="text-xs text-base-content/60">${item.country}</span></a></li>`;
      });
      html += "</ul></div>";
    }

    // Render resorts
    if (grouped.resort.length > 0) {
      html +=
        '<div class="mb-4"><h4 class="font-semibold text-sm mb-2 text-base-content/60">Ski Resorts</h4><ul class="menu">';
      grouped.resort.forEach((item) => {
        html += `<li><a href="${item.url}" class="flex items-center gap-2"><span>⛷️</span><div class="flex flex-col items-start"><span>${item.name}</span><span class="text-xs text-base-content/60">${item.state}, ${item.country}</span></div></a></li>`;
      });
      html += "</ul></div>";
    }

    searchResults.innerHTML = html;
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

  // Open modal and load data
  searchButton.addEventListener("click", () => {
    modal.showModal();
    loadSearchData();
    searchInput.focus();
  });

  // Search on input
  searchInput.addEventListener("input", (e) => {
    debouncedSearch(e.target.value);
  });

  // Clear results when modal closes
  modal.addEventListener("close", () => {
    searchInput.value = "";
    searchResults.innerHTML = "";
    searchEmpty.classList.add("hidden");
  });

  // Keyboard shortcut: Cmd/Ctrl + K to open search
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault();
      modal.showModal();
      loadSearchData();
      searchInput.focus();
    }
  });
})();
