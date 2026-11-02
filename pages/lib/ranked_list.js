// Ranked lists: server order is the 7d default; any other key sorts descending, tapping it again restores.
export function initRankedLists() {
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
      () => apply(button.dataset.sort === current ? "7d" : button.dataset.sort),
    );
  });

  const requested = new URLSearchParams(location.search).get("sort");
  if (
    requested &&
    [...table.querySelectorAll("thead button[data-sort]")].some((b) =>
      b.dataset.sort === requested
    )
  ) {
    apply(requested);
  }
}
