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
    $toggle.checked ? "metric" : "imperial",
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
