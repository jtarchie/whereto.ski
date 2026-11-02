import { Map, Popup } from "./maplibre/maplibre-gl.mjs";
import { isMetric, km, loadIndex, snowLevel } from "./lib/shared.js";

const root = document.documentElement;
const dark = matchMedia("(prefers-color-scheme: dark)").matches;
const STYLE = `https://tiles.openfreemap.org/styles/${
  dark ? "dark" : "positron"
}`;
const NEARBY_KM = 150;

// MapLibre can't parse oklch tokens; a 1px canvas resolves them to rgb.
const ctx = document.createElement("canvas").getContext("2d", {
  willReadFrequently: true,
});
function rgb(name) {
  ctx.clearRect(0, 0, 1, 1);
  ctx.fillStyle = getComputedStyle(root).getPropertyValue(name).trim();
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return `rgb(${r},${g},${b})`;
}

const metric = isMetric();
const amount = (inches) =>
  metric
    ? `${Math.round(inches * 2.54)} cm`
    : `${Math.round(inches * 10) / 10}″`;

function unavailable(el) {
  el.querySelector(".maplibregl-canvas-container")?.remove();
  const status = el.querySelector("[data-map-status]");
  status.hidden = false;
  status.textContent = "Map unavailable";
}

function resortsFor(el, entries) {
  const all = entries.filter((d) => d.type === "r" && d.at);
  const { country, region, lat, lon } = el.dataset;
  if (lat) {
    const center = [parseFloat(lat), parseFloat(lon)];
    return all.filter((r) => km(center, r.at) <= NEARBY_KM);
  }
  return all.filter((r) =>
    (!country || r.country === country) && (!region || r.region === region)
  );
}

function draw(el, resorts, steps) {
  const here = el.dataset.url;
  const features = resorts.map((r) => ({
    type: "Feature",
    geometry: { type: "Point", coordinates: [r.at[1], r.at[0]] },
    properties: {
      name: r.name,
      url: r.url,
      snow: r.snow,
      level: snowLevel(r.snow, steps),
      here: r.url === here,
    },
  }));
  const lons = features.map((f) => f.geometry.coordinates[0]);
  const lats = features.map((f) => f.geometry.coordinates[1]);

  const map = new Map({
    container: el,
    style: STYLE,
    bounds: [
      [Math.min(...lons), Math.min(...lats)],
      [Math.max(...lons), Math.max(...lats)],
    ],
    fitBoundsOptions: { padding: 32, maxZoom: 9 },
    cooperativeGestures: true,
    keyboard: false,
    dragRotate: false,
    pitchWithRotate: false,
    attributionControl: { compact: true },
  });
  // The list is the accessible path; keep the canvas out of the tab order and the a11y tree.
  map.getCanvas().setAttribute("aria-hidden", "true");
  map.getCanvas().tabIndex = -1;

  let loaded = false;
  map.on("error", () => {
    if (!loaded) unavailable(el);
  });
  map.on("load", () => {
    loaded = true;
    el.querySelector("[data-map-status]").hidden = true;
    const colors = [1, 2, 3, 4, 5].flatMap((n) => [n, rgb(`--c-mark-${n}`)]);
    map.addSource("resorts", {
      type: "geojson",
      data: { type: "FeatureCollection", features },
    });
    map.addLayer({
      id: "resorts",
      type: "circle",
      source: "resorts",
      paint: {
        "circle-color": [
          "match",
          ["get", "level"],
          ...colors,
          rgb("--c-ink-3"),
        ],
        "circle-radius": [
          "case",
          ["get", "here"],
          9,
          ["interpolate", ["linear"], ["get", "level"], 0, 3, 5, 7],
        ],
        "circle-stroke-width": ["case", ["get", "here"], 3, 1],
        "circle-stroke-color": [
          "case",
          ["get", "here"],
          rgb("--c-ink"),
          rgb("--c-canvas"),
        ],
      },
      layout: { "circle-sort-key": ["get", "level"] },
    });

    const popup = new Popup({ closeButton: false, offset: 10 });
    map.on("mouseenter", "resorts", (e) => {
      const { name, snow } = e.features[0].properties;
      map.getCanvas().style.cursor = "pointer";
      popup.setLngLat(e.lngLat).setText(`${name} · ${amount(snow)} next 7 days`)
        .addTo(map);
    });
    map.on("mouseleave", "resorts", () => {
      map.getCanvas().style.cursor = "";
      popup.remove();
    });
    map.on("click", "resorts", (e) => {
      location.href = e.features[0].properties.url;
    });
  });
}

const maps = document.querySelectorAll("[data-map]");
loadIndex()
  .then(({ entries, steps }) =>
    maps.forEach((el) => {
      const resorts = resortsFor(el, entries);
      resorts.length ? draw(el, resorts, steps) : unavailable(el);
    })
  )
  .catch(() => maps.forEach(unavailable));
