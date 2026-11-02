import { isMetric, pref } from "./shared.js";

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

const resortZone = () =>
  document.querySelector("[data-resort-tz]")?.dataset.resortTz;

function timeZone() {
  const saved = pref("preferredTimezone") || "auto";
  const zone = saved === "auto"
    ? undefined
    : saved === "resort"
    ? resortZone()
    : saved;
  try {
    new Intl.DateTimeFormat(undefined, { timeZone: zone });
    return zone;
  } catch {
    return undefined;
  }
}

export function formatAll(root = document) {
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

function initTimezoneSelect($tz) {
  const detected = Intl.DateTimeFormat().resolvedOptions().timeZone;
  $tz.options[0].textContent = `Auto (${detected})`;
  if (!resortZone()) {
    $tz.options[1].textContent = "Resort local (on resort pages)";
  }
  (Intl.supportedValuesOf?.("timeZone") ?? []).forEach((zone) => {
    $tz.add(new Option(zone.replaceAll("_", " "), zone));
  });
  $tz.value = pref("preferredTimezone") || "auto";
  if (!$tz.value) $tz.value = "auto";
}

// Listeners attach at script load (script is at end of body); the returned fn is the DOMContentLoaded step.
export function initUnits() {
  const $units = document.getElementById("unit-toggle");
  const $tz = document.getElementById("tz-select");

  $units.addEventListener("change", () => {
    pref("preferredUnits", $units.checked ? "metric" : "imperial");
    formatAll();
  });

  $tz.addEventListener("change", () => {
    pref("preferredTimezone", $tz.value);
    formatAll();
  });

  return () => {
    $units.checked = isMetric();
    initTimezoneSelect($tz);
    formatAll();
  };
}
