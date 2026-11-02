import { el } from "./dom.js";
import { formatAll } from "./format.js";
import { loadSearchData, searchIndex } from "./search.js";
import { km, pref, snowLevel } from "./shared.js";

const NEAR_KM = 300;

function nearMeTable(rows, steps) {
  const table = el("table", "ranked");
  const head = el("tr");
  [["rank", ""], ["who", "Resort"], ["num w-16 md:w-20", "Away"], [
    "num",
    "7 days",
  ]]
    .forEach(([cls, label]) => {
      const th = el("th", cls, label);
      th.scope = "col";
      head.append(th);
    });
  table.append(el("thead"), el("tbody"));
  table.tHead.append(head);
  rows.forEach((r, index) => {
    const tr = el("tr");
    tr.dataset.hasSnow = r.snow > 0;
    const who = el("td", "who");
    const link = el("a", "", r.name);
    link.href = r.url;
    who.append(
      link,
      el("span", "place", [r.region, r.country].filter(Boolean).join(" · ")),
    );
    const distance = el("data", "", `${Math.round(r.km)} km`);
    distance.value = r.km.toFixed(1);
    distance.dataset.k = "d";
    const level = snowLevel(r.snow, steps);
    const snow = el(
      "td",
      level ? `num bg-snow-${level} text-on-snow-${level}` : "num",
    );
    if (level) {
      const amount = el("data", "", `${r.snow}″`);
      amount.value = r.snow;
      amount.dataset.k = "s";
      snow.append(amount);
    } else snow.textContent = "–";
    const dist = el("td", "num");
    dist.append(distance);
    tr.append(el("td", "rank", String(index + 1)), who, dist, snow);
    table.tBodies[0].append(tr);
  });
  return table;
}

function showNearMeError(section, list, message) {
  section.replaceChildren(el("p", "mb-4 border-l-4 py-1 pl-3", message));
  section.hidden = false;
  list.hidden = false;
}

// Location stays in the browser: it is never sent anywhere or put in the URL.
export function initNearMe() {
  const chip = document.querySelector("[data-near-me]");
  const list = document.querySelector("[data-ranked-section]");
  if (!chip || !list || !navigator.geolocation) return;
  if (pref("nearMeDenied")) return;
  chip.hidden = false;
  chip.setAttribute("aria-pressed", "false");

  const section = el("section");
  section.id = "near-me";
  section.setAttribute("aria-live", "polite");
  section.hidden = true;
  list.before(section);

  function reset() {
    chip.setAttribute("aria-pressed", "false");
    section.hidden = true;
    list.hidden = false;
  }

  function render(position, { entries, steps }) {
    const here = [position.coords.latitude, position.coords.longitude];
    const nearby = entries
      .filter((d) => d.type === "r" && d.at)
      .map((d) => ({ ...d, km: km(here, d.at) }))
      .filter((d) => d.km <= NEAR_KM);
    const snowy = nearby.filter((d) => d.snow > 0)
      .sort((a, b) => b.snow - a.snow || a.km - b.km);
    const rows = snowy.length
      ? snowy.slice(0, 25)
      : nearby.sort((a, b) => a.km - b.km).slice(0, 10);
    const range = el("data", "", `${NEAR_KM} km`);
    range.value = NEAR_KM;
    range.dataset.k = "d";

    const heading = el("h2", "mb-1", "Near you");
    const note = el("p", "mb-2 text-sm text-ink-2");
    if (!nearby.length) {
      note.append("No resorts within ", range, " of you.");
    } else if (!snowy.length) {
      note.append(
        "No snow forecast in the next 7 days within ",
        range,
        ". Nearest resorts:",
      );
    } else {
      note.append(
        `Snow in the next 7 days at ${snowy.length} of ${nearby.length} resorts within `,
        range,
        ".",
      );
    }
    section.replaceChildren(heading, note);
    if (rows.length) section.append(nearMeTable(rows, steps));
    formatAll(section);
    list.hidden = true;
    section.hidden = false;
    chip.setAttribute("aria-pressed", "true");
  }

  chip.addEventListener("click", () => {
    if (chip.getAttribute("aria-pressed") === "true") return reset();
    chip.textContent = "Locating…";
    chip.setAttribute("aria-busy", "true");
    const done = () => {
      chip.textContent = "Near me";
      chip.removeAttribute("aria-busy");
    };
    navigator.geolocation.getCurrentPosition(
      (position) =>
        loadSearchData().then(() => {
          done();
          const index = searchIndex();
          index ? render(position, index) : showNearMeError(
            section,
            list,
            "Couldn't load resorts. Try again.",
          );
        }),
      (error) => {
        done();
        if (error.code === error.PERMISSION_DENIED) {
          pref("nearMeDenied", "1");
          chip.hidden = true;
          reset();
        } else {
          showNearMeError(
            section,
            list,
            "Couldn't find your location. Try again.",
          );
        }
      },
      { timeout: 10000, maximumAge: 600000 },
    );
  });
}
