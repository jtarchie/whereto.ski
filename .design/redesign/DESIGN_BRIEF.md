# Design Brief: whereto.ski Redesign

## Problem

It's Thursday night, a storm is coming, and I have a car and a free Saturday.
I want to know which mountain within driving range gets the most snow, when it
lands, and whether it falls as snow or rain at the base. Today I have to pick a
country from an alphabetical list, then a state, then scan a table of 16 date
columns, then open each resort and read two 11-column tables. The "Best Days"
score says every day is "Fair 40" and doesn't tell me why. Times are shown in
New York time no matter where I or the resort are. Some numbers are simply
wrong (elevation in meters labeled feet, freezing level at 57,000 ft).

## Solution

Open the site and the answer is on the first screen: where it's snowing now
and where it will snow next, ranked by amount, with the timing. Narrowing
down (to a country, a state, near me) re-ranks the same list instead of
sending you down a tree. A resort page answers four questions in order — how
much fell recently, how much is coming and when, will it be snow or rain at
my elevation, and what's nearby that's doing better — with the full hourly
detail one tap away. A map shows the same ranking spatially. Everything is in
your units and your timezone, which you can change.

## Experience Principles

1. **Answer first, detail on demand** — Every page leads with the number that
   decides the trip (snow amount + when). Tables, hourly data and terrain
   stats are progressive disclosure, never the opening act.
2. **Facts over verdicts** — Show measured/forecast values with units and
   source; no opaque scores. A day only gets called out ("Powder Sat · 9″")
   when there is real snow to call out. Uncertain data (model snow depth) is
   labeled as such.
3. **Color means snow** — The neutral interface stays grey; the single
   cold-blue intensity scale encodes snowfall amount everywhere (lists, bars,
   map dots). If it's blue, it's snow. Rain/warm risk gets one warning hue.

## Aesthetic Direction

- **Philosophy**: Dieter Rams (functionalist). Strict 4px grid, one type
  scale, tabular numerals, hairline dividers over shadows, minimal motion
  (state changes only).
- **Tone**: Calm, precise, trustworthy. Excitement comes from the numbers, not
  the chrome.
- **Reference points**: OpenSnow (numbers-first resort lists), Windy (color as
  data), weather.gov (plain, credible forecast presentation).
- **Anti-references**: Ad-heavy resort portals (OnTheSnow, Snow-Forecast),
  generic SaaS/daisyUI card UI, emoji-as-icons, gradients, animated
  "shimmer" badges, medal emojis for rankings.

## Existing Patterns

Starting state is daisyUI defaults; the redesign **replaces** rather than
extends (decided: drop daisyUI).

- Typography: daisyUI default sans; `font-black` headings with gradient
  underline pseudo-elements. → Replace with system UI stack
  (`system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`), tabular nums,
  no web fonts.
- Colors: daisyUI `winter` (light) / `night` (dark) themes, ad-hoc
  `cyan-*`/`blue-*` utilities, rating colors per ski-day card. → Replace with
  token set (Phase 4): neutral greys + snow intensity ramp + one warning hue,
  light and dark.
- Spacing: Tailwind default scale, used inconsistently. → 4px base scale via
  Tailwind v4 `@theme`.
- Components to keep conceptually: native `<dialog>` for search/settings,
  breadcrumbs, `Cmd/Ctrl+K` search shortcut, lazy-loaded compact search index
  (`docs/assets/search-data.json`), localStorage preferences.
- Build constraints: ERB templates in `pages/`, routing by filename
  placeholders, Herb lint/format in CI, Tailwind v4 CLI + esbuild.

## Data Changes (Ruby pipeline)

Required to deliver the information the design leads with.

| Change | Where | Why |
| --- | --- | --- |
| `timezone=auto`; store resort IANA tz | `open_meteo.rb` | Day boundaries are resort-local; today all resorts use `America/New_York` |
| `past_days=3` | `open_meteo.rb` | "Fresh snow, last 72h" — the second thing a skier asks |
| hourly `snow_depth` | `open_meteo.rb` | Model-estimated depth, labeled "model est." |
| Base + summit forecast (`elevation=` param, multi-location request) | `open_meteo.rb`, `resort.rb` | Snow/rain at base vs. summit; temps at both. Doubles API weight — fallback: summit only |
| Freezing level: stop double conversion (API already returns ft with `precipitation_unit=inch`) | `context.rb` | Shows 57,047 ft today |
| Elevations: OpenSkiMap values are meters | `resort.rb`/`context.rb` | Labeled ft today |
| Expose OpenSkiMap stats: runs by difficulty (count, km), lifts by type, vertical, locality (town) | SQLite view, `resort.rb` | Terrain context for "is it worth the drive" |
| Nearby resorts (haversine, build time, top N within ~150 km) | `context.rb` | Compare alternatives; the founding Winter Park → Steamboat story |
| Emit raw values (inches, °F, mph, ISO UTC timestamps) in data attributes; no dual-unit spans | templates + helpers | Client formats units/time; halves HTML weight |
| Search index gains lat/lon + 7-day snow | `builder.rb` | "Near me" and snow-aware search results |
| Fail-safe on API error payloads (`KeyError: "daily"`) | `open_meteo.rb` | Daily build failing since 2026-07-20; separate fix, prerequisite for live data |

## Component Inventory

| Component | Status | Notes |
| --- | --- | --- |
| Site header (logo, search, settings) | Modify | Text wordmark, no sparkle icon; search field visible on desktop, icon on mobile |
| Search dialog | Modify | Keep lazy index + Cmd/Ctrl+K; results show 7-day snow; escape output (currently injects names via `innerHTML`) |
| Settings dialog | Modify | Units (imperial/metric), timezone (auto-detected / resort local / pick any IANA zone via `Intl.supportedValuesOf`), snow-only filter |
| Formatter script | New | Reads `data-*` raw values, formats via `Intl.NumberFormat`/`DateTimeFormat` per prefs; re-runs on pref change |
| Snow amount cell / chip | New | Number + unit, background from snow intensity ramp; zero renders muted "0" |
| Ranked resort list | New | Replaces 3 Snow Now tables + state forecast table + country/state link lists. Rows: name, place, 24h / 72h-past / 7d / 16d, next snow day. Sortable by column; filter chips (country, state, near me) |
| 16-day snow strip | New | Inline SVG bars per day (resort-local days), height = amount, ramp color; compact variant in list rows |
| Resort summary | New | Fresh 72h, next 24h, next 7d, 16d; snow level vs base/summit; base & summit temp; wind |
| Day callout | New (replaces Best Days score) | Only when snow ≥ threshold: "Powder Sat · 9″"; otherwise nothing |
| Hourly detail | Modify | Inside `<details>`; fewer columns (time, conditions, snow, temp, wind/gust, freezing level); times in viewer TZ |
| Daily table | Modify | Fallback/detail view beneath strip; resort-local days, labeled "Days in resort local time" |
| Terrain facts | New | Runs by difficulty (bar or counts), lifts, vertical, elevation range, website link |
| Nearby resorts | New | 5–8 nearest with distance + 7d snow, ranked by snow |
| Map | New | MapLibre GL + OpenFreeMap tiles, lazy (IntersectionObserver). Home/country/state: dots colored by 7d snow, click → resort. Resort: small locator with nearby resorts. List remains primary; map is never the only path |
| Empty state | New | "No snow forecast in {place} through {date}." + link to snowiest region worldwide |
| Breadcrumbs | Modify | Restyle; drop "All" root label in favor of "World" |
| Footer | Modify | Data attribution (Open-Meteo, OpenSkiMap/OSM — required by license), updated-at in viewer TZ |
| About page | Modify | Restyle; remove duplicated "Our Mission" |
| Emoji icons, medal ranks, shimmer badges, gradient underlines | Remove | Anti-references |

## Key Interactions

- **Landing**: home renders a global ranked list (by 7-day snow, ties by 16d)
  server-side; first screen on a phone shows the top ~5 resorts with amounts
  and timing. No interaction needed to get the answer.
- **Narrowing**: country/state pages are the same ranked list pre-filtered,
  with static URLs (SEO). "Near me" is opt-in: tapping requests geolocation
  once, then client-side re-ranks by distance-weighted snow using the search
  index (lat/lon). Denied permission → hide the chip, no nagging.
- **Sorting**: tapping a column header (24h, 72h past, 7d, 16d, a specific
  day) re-sorts descending; tap again restores default. `aria-sort` updated.
- **Preferences**: units and timezone apply instantly (no reload) and persist
  in localStorage. Defaults: units from `navigator.language` (en-US →
  imperial), timezone from `Intl.DateTimeFormat().resolvedOptions().timeZone`.
  The active timezone is shown next to hourly times ("Times in MST · change").
- **Time semantics**: hourly rows, "updated at", "snowing now" → viewer's TZ
  (or chosen override / resort local). Daily buckets are always resort-local
  calendar days and labeled so.
- **Detail on demand**: hourly table and full daily table live in `<details>`;
  open state not persisted.
- **Map**: loads only when scrolled into view; until then, a static
  placeholder of matching height (no layout shift). Dots are keyboard
  reachable via the list, not the canvas.
- **No-JS**: pages render complete with server-default formatting (imperial,
  resort-local times labeled with zone); sorting, prefs, near-me, map are
  enhancements.

## Responsive Behavior

- **Mobile first (≈375–430px)**: ranked list is a single column of rows (name +
  place line, then 24h / 7d / next-snow, mini strip). Only 3 numeric columns
  visible; others available via sort menu. Search is a header icon → full
  dialog.
- **Tablet (≥768px)**: list gains 72h-past and 16d columns; map appears beside
  or below list.
- **Desktop (≥1024px)**: two columns on list pages (list | sticky map); resort
  page splits summary + strip (main) and terrain + nearby (aside). Max content
  width ~1200px.
- Tables never require horizontal scrolling on mobile for the primary info;
  only the hourly detail table may scroll, with a sticky time column.

## Accessibility Requirements

- WCAG 2.2 AA. Re-enable `color-contrast` in `.pa11yci` (currently ignored).
- Snow intensity never conveyed by color alone — the number is always present.
- All interactive elements keyboard reachable; visible focus ring (token);
  dialogs trap focus and return it (native `<dialog>`).
- Sortable headers are `<button>`s inside `<th>` with `aria-sort`.
- SVG strips get `role="img"` + `aria-label` summarizing ("16-day snow: 9 in
  Sat, 4 in Sun, …") and a table fallback in `<details>`.
- Map canvas is `aria-hidden` supplementary; equivalent info is in the list.
- Respect `prefers-reduced-motion` and `prefers-color-scheme`.
- Hit targets ≥ 44px on touch.

## Performance Budget

- HTML ≤ 100 KB per page (state pages are ~205 KB today).
- CSS ≤ 30 KB (100 KB today). Core JS ≤ 10 KB gzipped.
- Map JS (~250 KB gz) and tiles load only on intersection.
- No web fonts.

## Out of Scope

- Accounts, favorites synced across devices (localStorage favorites can be a
  later task, not this brief).
- Historical/season snowfall archives beyond `past_days=3`.
- Resort-reported conditions (lifts open, official base depth) — no data source.
- Avalanche, road, or traffic data; drive times (straight-line distance only).
- Ads, monetization changes, newsletter.
- New countries or resort data sources (OpenSkiMap remains the source).
- Localization of UI copy (units/time localize; text stays English).
- Changing URL structure — all existing paths remain; Snow Now pages redirect.
