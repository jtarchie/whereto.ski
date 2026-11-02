// Shared by main.js (input.js) and map.js; keep free of DOM access at import time.

// Storage throws when blocked (Safari, cookies off); memory fallback keeps toggles working for this page view.
const memory = new Map();
export function pref(key, value) {
  try {
    if (value === undefined) return localStorage.getItem(key);
    localStorage.setItem(key, value);
  } catch {
    if (value === undefined) return memory.get(key) ?? null;
    memory.set(key, String(value));
  }
}

export const isMetric = () => {
  const saved = pref("preferredUnits");
  return saved ? saved === "metric" : navigator.language !== "en-US";
};

// steps come from the search index (Ruby Units::SNOW_STEPS), never a literal here.
export const snowLevel = (inches, steps) =>
  inches <= 0 ? 0 : steps.filter((step) => inches >= step).length + 1;

export function km([lat1, lon1], [lat2, lon2]) {
  const rad = Math.PI / 180;
  const h = Math.sin(((lat2 - lat1) * rad) / 2) ** 2 +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) *
      Math.sin(((lon2 - lon1) * rad) / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

// Index: { steps, cl: [countries], d: [{t c/s/r, n, c: index into cl, s, u, l: [lat, lon], w: 7d snow}] }; throws without steps so callers take their "unavailable" path.
export function decodeIndex(raw) {
  const steps = raw.steps;
  if (!Array.isArray(steps) || !steps.length) {
    throw new Error("search index has no steps");
  }
  const entries = raw.d.map((item) => ({
    type: item.t,
    name: item.n,
    country: typeof item.c === "number" ? raw.cl[item.c] : undefined,
    region: item.s,
    url: item.u,
    snow: item.w ?? 0,
    at: item.l,
  }));
  return { entries, steps };
}

export const loadIndex = () =>
  fetch("/assets/search-data.json")
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.json();
    })
    .then(decodeIndex);
