// MapLibre is ~400 KB gz, so it loads only when a map placeholder nears the viewport.
export function initMapLoader() {
  const maps = document.querySelectorAll("[data-map]");
  if (!maps.length || !("IntersectionObserver" in window)) return;
  const status = (text) =>
    maps.forEach((m) =>
      m.querySelector("[data-map-status]").textContent = text
    );
  const observer = new IntersectionObserver((entries) => {
    if (!entries.some((e) => e.isIntersecting)) return;
    observer.disconnect();
    status("Loading map…");
    const css = document.createElement("link");
    css.rel = "stylesheet";
    css.href = "/assets/maplibre/maplibre-gl.css";
    const js = document.createElement("script");
    js.type = "module";
    js.src = "/assets/map.js";
    js.onerror = () => status("Map unavailable");
    document.head.append(css, js);
  }, { rootMargin: "200px" });
  maps.forEach((m) => observer.observe(m));
}
