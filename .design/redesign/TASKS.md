# Build Tasks: whereto.ski Redesign

Generated from: .design/redesign/DESIGN_BRIEF.md Also:
INFORMATION_ARCHITECTURE.md, DESIGN_TOKENS.css Date: 2026-11-01

Conventions for every task: `# frozen_string_literal: true`, no hash shorthand,
`rake fmt` clean, Herb lint passes, specs updated in the same task (the suite
builds the whole site once via `SharedBuild`). Verify visually with
`rake fast` + `ruby -run -ehttpd docs/ -p8000`.

## Foundation

- [x] **1. Build survives API errors**: `Forecast::OpenMeteo#fetch_data` treats
      a response without `daily` (Open-Meteo `{"error":true,"reason":…}`) as a
      retryable failure with a retry cap, and logs `reason`; the daily build
      stops failing on `KeyError: "daily"` (failing since 2026-07-20). Done =
      spec stubbing an error payload then success passes; `rake build[20]`
      succeeds locally with the real API. _Modifies: `open_meteo.rb`,
      `open_meteo_spec.rb`._

- [x] **2. Forecast data v2**: request `timezone=auto`, `past_days=3`, hourly
      `snow_depth`, and base + summit points (multi-location `elevation=`
      request; fallback: summit only if rate budget breaks). Store resort IANA
      timezone; expose past-72h, next-24h, next-7d, 16d totals per elevation;
      stop double-converting freezing level (API already returns ft). Make
      `stub_weather_api` deterministic per resort (seeded by lat/lon) with a
      spread of dry / trace / snow-day / powder / 12″+ resorts, so every snow
      step and the empty state appear in `rake fast`. Done = specs cover totals,
      resort-local day bucketing, freezing level in ft. _Modifies:
      `open_meteo.rb`, `forecast.rb`, `resort.rb`, `context.rb`,
      `spec_helper.rb`._

- [x] **3. Resort terrain + geography data**: extend the SQLite `resorts` view
      with locality, runs by difficulty (count, km), lifts by type, vertical;
      treat OpenSkiMap elevations as meters (fix "2,105 ft" mislabel); compute
      nearby resorts (haversine, ≤150 km, top 8) once at build start. Done =
      Steamboat shows town "Steamboat Springs", 199 runs, 20 lifts, 1,102 m
      vertical in a spec. _Modifies: `Resort.from_sqlite` (join `features`
      payload JSON for the extra fields, so the LFS database needn't change),
      `openskimap.rb` view SQL (same fields, for the next `rake scrape`),
      `resort.rb`, `context.rb`._

- [x] **4. Token swap + layout shell (Dieter Rams)**: move `DESIGN_TOKENS.css` →
      `pages/tokens.css`, import it in `input.css`, remove daisyUI (npm +
      `@plugin`) and all legacy CSS (gradients, shimmer, snowfall keyframes,
      gradient underlines). Base layer: system font, `tabular-nums`, ink links
      with underline, `:focus-visible` ring token, reduced-motion. Rebuild
      `_layout.html.erb`: text wordmark, search + settings buttons (44px),
      native `<dialog>` styled with tokens, footer with About/Contact/Support/
      GitHub, Open-Meteo + OpenSkiMap/OSM attribution, "Updated {time}",
      `<link rel="canonical">`. Done = every page renders in the new shell, no
      daisyUI class remains in `pages/`, light + dark both readable. _New:
      tokens, shell. Removes: daisyUI._

- [x] **5. Formatter: units + timezone on the client**: ERB helpers emit one
      value with raw data
      (`<data class="snow-3" value="4.2" data-u="in">4.2″</data>`,
      `<time datetime="…Z">`) instead of dual imperial/metric spans; `input.js`
      formats via `Intl.NumberFormat`/`DateTimeFormat` from prefs. Settings
      dialog: units toggle, timezone select (Auto (detected) / Resort local /
      any `Intl.supportedValuesOf('timeZone')`), snow-only filter; live apply,
      localStorage persist; no-JS default = imperial + resort-local labeled
      zone. Snow helper maps inches → `snow-N` class per token thresholds. Done
      = Capybara spec flips units and timezone and sees values change; Bayern
      region page HTML measurably smaller. _New: `snow_value`, `time_value`
      helpers; modifies `context.rb`, `snow_helper.rb`, `daily.rb`, `input.js`._

## Core UI

- [x] **6. Resort page — decision block**: replace Best Days score and stat
      cards with: header (name, town · region · country, elevation range,
      updated), snow summary (Past 72h · Next 24h · Next 7 days · 16 days, hero
      numbers), day callout only when ≥2″ ("Powder Sat · 9″"), 16-day snow strip
      (inline SVG, `mark-N` fills, resort-local days labeled, `role="img"` +
      summary `aria-label`), Snow or rain? (snow level vs base/summit,
      base/summit temps, wind/gusts, next 3 days; amber when snow level above
      base). First screen on a 390px phone shows summary + callout. Delete
      `best_days_compact_spec.rb`; new spec asserts summary values and callout
      logic. _Depends on: 2, 4, 5. New: summary, strip, callout, snow/rain._

- [x] **7. Resort page — context + detail**: nearby list (5–8, 7d snow,
      distance), "More snow nearby" line (≥2× and ≥3″ more, within 150 km),
      terrain block (vertical, runs by difficulty, lifts, website), `<details>`
      hourly (48h, 6 columns, viewer TZ with "Times in {zone} · change"), and
      `<details>` daily table (16 days, resort-local). Done = Steamboat page
      passes vnu; hourly table scrolls only inside its container on mobile.
      _Depends on: 3, 6._

- [x] **8. Ranked list + Region page**: shared ranked-list partial (rank, name +
      place, 24h, 7d, next snow, mini strip; 72h-past and 16d from md up), sort
      headers as `<button>` with `aria-sort`, per-day sort on desktop via strip
      header, `?sort=` via `replaceState`, snow-only filter hook, status line,
      scope chips (Near me placeholder hidden until task 12), empty state ("No
      snow forecast in {Region} through {date}" + snowiest sibling). Region page
      uses it for all resorts. Rewrite `date_sorting_spec.rb` against it. Done =
      Bayern page ≤100 KB HTML and sortable by keyboard. _New: ranked list,
      status line, scope chips, empty state. Depends on: 4, 5._

- [x] **9. Country + Home pages, retire Snow Now**: large countries = top 25 +
      regions ranked table; small countries (≤20) = all resorts; home = global
      top 25 + countries ranked + dry-countries list. Delete the three
      `*snow-now` templates; generate `docs/_redirects` (301 to parent) from the
      same small-country rule as builder + search index; update `rake a11y` URLs
      and `.pa11yci` URL list; confirm where `sitemap.xml` comes from (no
      generator in repo) and drop snow-now URLs from it. Done = `/snow-now` 301s
      in `wrangler pages dev`; `build_spec` updated. _Reuses: ranked list (8).
      New: sub-area table._

## Interactions & States

- [x] **10. Search**: restyle dialog with tokens; build results with DOM APIs /
      `textContent` (no `innerHTML` with OSM names); add 7d snow to each resort
      result and lat/lon (3 dp) to the index; `/` shortcut besides Cmd/Ctrl+K;
      empty copy "No matches. Try a town or region name." Covers: loading, error
      (index fetch fails), empty, results. Rewrite `search_spec.rb` and
      `mobile_search_spec.rb`. _Modifies: search dialog,
      `generate_search_index`._

- [x] **11. Map (MapLibre + OpenFreeMap, lazy)**: separate esbuild entry
      `map.js` loaded on IntersectionObserver; fixed-height placeholder
      (`--size-map`, no layout shift); overview on home/country/region (dots in
      `mark-N` by 7d snow, click → resort, fitted to scope), locator on resort
      pages (resort + nearby). Canvas `aria-hidden`; list remains the accessible
      path. Covers: not-yet-loaded, loading, tile failure (placeholder stays
      with "Map unavailable"), dark style. Done = core `main.js` still ≤10 KB
      gz. _New dep: `maplibre-gl`. New: map._

- [x] **12. Near me**: chip on home/country/region; on tap request geolocation
      once, re-rank resorts within ~300 km by 7d snow from the search index,
      render with the ranked-list markup client-side. Covers: granted, denied
      (chip hides, no re-prompt), unavailable, no snow nearby (empty state).
      _Depends on: 8, 10._

## Responsive & Polish

- [x] **13. About + meta copy**: rewrite About (what, story, data & methodology
      incl. thresholds and model snow-depth caveat, license); remove duplicate
      "Our Mission"; update page `description`/`title` front matter to lead with
      snow numbers. _Modifies: `about.html.erb`, front matter._

- [ ] **14. Responsive pass**: verify at 375 / 768 / 1024 / 1280, light + dark:
      no horizontal page scroll; list columns per IA; resort page two-column
      ≥1024; breadcrumbs scroll on mobile; 44px targets. Breakpoints: md, lg,
      xl.

- [ ] **15. Accessibility + performance pass**: re-enable `color-contrast` in
      `.pa11yci`; `rake a11y` (vnu + pa11y) clean; keyboard-only run through
      storm-chaser and lookup flows; dialogs return focus; budgets measured on
      `rake fast` output: HTML ≤100 KB (Bayern, Tirol, Hokkaido), CSS ≤30 KB,
      core JS ≤10 KB gz, no web fonts.

## Review

- [ ] **Design review**: run `/design-review` against the brief.
