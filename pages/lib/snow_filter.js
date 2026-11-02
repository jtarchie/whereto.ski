import { pref } from "./shared.js";

export function initSnowFilter() {
  const toggle = document.getElementById("filter-snow-toggle");
  if (!toggle) return;
  const filterSnowOnly = pref("filterSnowOnly") === "true";
  toggle.checked = filterSnowOnly;
  if (filterSnowOnly) document.body.classList.add("filter-snow-only");

  toggle.addEventListener("change", () => {
    document.body.classList.toggle("filter-snow-only", toggle.checked);
    pref("filterSnowOnly", toggle.checked);
  });
}
