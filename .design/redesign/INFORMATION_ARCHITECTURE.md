# Information Architecture: whereto.ski

Built on the existing filename routing (`pages/**/*.html.erb`, placeholders
`[resort]`, `[state]`, `[country]`). No URL changes; three templates removed.

## Site Map

- Home — global ranking `/`
  - Country `/countries/:country`
    - Region `/states/:region` *(large countries only; >20 resorts)*
      - Resort `/resorts/:resort`
    - Resort `/resorts/:resort` *(small countries link directly)*
- About `/about`
- 404 `/404.html`
- Search index `/assets/search-data.json` *(data, not a page)*

Removed templates → 301 redirects (generated `_redirects` at build, one line
per entity; ~350 lines, under Cloudflare Pages' 2,000 static limit):

| Old | New |
| --- | --- |
| `/snow-now` | `/` |
| `/countries/:country-snow-now` | `/countries/:country` |
| `/states/:region-snow-now` | `/states/:region` |

Resort pages are the front door (search-engine landings); every page must
stand alone without assuming the visitor came from home.

## Navigation Model

- **Primary navigation**: none beyond the wordmark (→ `/`). The ranked list
  *is* the navigation. Max header items: wordmark, search, settings.
- **Secondary navigation**:
  - Breadcrumbs on every page below home: `World › Country › Region ›
    Resort` (Region omitted for small countries).
  - Scope chips at top of each ranked list: current scope + "Near me".
    Changing country/region = following a link (static page), not a
    client-side filter.
  - Sub-area tables (countries on home, regions on large country pages) link
    down a level.
  - Nearby resorts on resort pages link sideways.
- **Utility navigation**: search (dialog, Cmd/Ctrl+K, `/` key), settings
  (dialog: units, timezone, snow-only filter). Footer: About, Contact,
  Support, GitHub, data attribution, updated time.
- **Mobile navigation**: same header (wordmark, search icon, settings icon).
  No hamburger — nothing to hide. Breadcrumbs truncate middle items with
  horizontal scroll.

## Content Hierarchy

### Home `/`
1. One-line status: "Snow in the next 7 days at **N** resorts worldwide ·
   Updated {time, viewer TZ}" — orients and proves freshness.
2. Scope chips: `World` (active) · `Near me` — the narrowing affordance.
3. **Top 25 resorts by 7-day snow** — ranked list (name, country/region, 24h,
   7d, next snow day, mini strip). The answer to "where's the snow".
4. **Countries ranked by 7-day snow** — country, resorts with snow / total,
   top resort + amount. Path into geography.
5. Map (lazy) — dots colored by 7-day snow, all resorts. Spatial view of #3/#4.
6. Countries with no snow — compact alphabetical list (still reachable).

### Country `/countries/:country`
**Large (>20 resorts):**
1. Title + status line ("Snow at N of M resorts in the next 7 days").
2. Scope chips: `{Country}` · `Near me`.
3. Top 25 resorts in country — ranked list.
4. Regions ranked by 7-day snow — region, resorts with snow / total, top
   resort. Dry regions after, alphabetical.
5. Map (lazy), fitted to country.

**Small (≤20 resorts):** 1–2 as above, then **all resorts** ranked, then map.

**Empty state:** "No snow forecast in {Country} through {date}." + link to
snowiest country. List still shown (ranked by 16-day, then coldest summit).

### Region `/states/:region`
1. Title + breadcrumbs + status line.
2. Scope chips.
3. **All resorts** ranked (max 114). Columns sortable: 24h, 72h past, 7d,
   16d, and per-day (desktop: 16-day strip header is clickable per day).
4. Map (lazy), fitted to region.
5. Empty state as above, linking to snowiest region in same country, then
   worldwide.

### Resort `/resorts/:resort` — front door
1. Name, town · region · country, elevation range, "Updated {time}".
   Identity + freshness.
2. **Snow summary**: Past 72h · Next 24h · Next 7 days · 16 days. Day callout
   if warranted ("Powder Sat · 9″"). The decision numbers.
3. **Better nearby** line, only when a resort within ~150 km has meaningfully
   more 7-day snow (e.g. ≥2× and ≥3″ more): "More snow nearby: Steamboat, 14″
   (62 mi)". Serves search landings; the founding use case.
4. **16-day snow strip** (resort-local days, labeled).
5. **Snow or rain?** Freezing/snow level vs. base and summit; base and summit
   temps; wind/gusts — for the next 3 days.
6. Nearby resorts list (5–8, ranked by 7-day snow, with distance).
7. Terrain: vertical, runs by difficulty, lifts by type, website link.
8. `<details>` Hourly — next 48h, viewer TZ (or override), labeled zone.
9. `<details>` Daily table — 16 days, all metrics.
10. Locator map (lazy) with nearby resorts.
11. Attribution.

### About `/about`
1. What it is (one paragraph). 2. Story. 3. Data sources & methodology
(how each number is computed; model snow depth caveat). 4. License /
attribution.

## User Flows

### Storm chaser (primary)
1. Lands on `/` on phone.
2. Sees top 25 resorts worldwide by 7-day snow.
   - If a nearby resort is listed → taps it → Resort page.
   - Else taps `Near me` → permission prompt.
     - Granted → list re-ranks to resorts within ~300 km by 7-day snow
       (client-side from search index).
     - Denied/unavailable → chip hides; user scrolls to countries table →
       Country → Region.
3. On Resort page reads summary → strip (when) → snow/rain check.
   - If "More snow nearby" shown → taps → compares → decides.
4. Done (decision made). Optional: opens Hourly to time departure.

### Resort lookup from search engine (most traffic)
1. Lands on `/resorts/:resort` from Google.
2. Sees snow summary immediately; times in own TZ, units per locale.
3. Branches:
   - Satisfied → leaves.
   - "More snow nearby" / Nearby list → sideways to another resort.
   - Breadcrumb → Region ranking to compare all.

### Find a specific resort
1. Any page → search (icon, Cmd/Ctrl+K, `/`).
2. Types ≥2 chars → results grouped Resorts / Regions / Countries, each
   resort showing 7-day snow.
3. Enter/tap → page. No results → "No matches. Try a town or region name."

### Change units / timezone
1. Settings icon → dialog.
2. Units toggle, timezone select (Auto (detected: X) / Resort local / any
   IANA zone), snow-only filter.
3. Changes apply live behind the dialog; persisted in localStorage.

### Narrow by geography
1. `/` → countries table → `/countries/:c`.
   - Small country → full ranked list → Resort.
   - Large → top 25 + regions table → `/states/:r` → Resort.

## Naming Conventions

| Concept | Label in UI | Notes |
| --- | --- | --- |
| Ski area | **Resort** | Even for small hills; matches URLs and search |
| Sub-national area | **Region** | Covers states, prefectures, cantons. URLs stay `/states/` |
| Snowfall that already fell (past 72h) | **Past 72h** | Not "fresh", not "new" |
| Snowfall next 24h | **Next 24h** | |
| Snowfall next 7 days | **Next 7 days** (short: **7d**) | Default ranking metric everywhere |
| Snowfall over full forecast | **16 days** (short: **16d**) | |
| Model snow depth | **Snow depth (model est.)** | Always with the caveat |
| Freezing level | **Snow level** | Plain-language; tooltip explains ≈ freezing level |
| Lowest/highest lift-served elevation | **Base** / **Summit** | |
| Day with significant snow | **Powder day** (≥6″/15 cm), **Snow day** (≥2″/5 cm) | Only labels; no scores |
| Resort-local calendar days | "Days in {resort} time" | Shown once above strip/table |
| Viewer's timezone | "Times in {zone abbr}" + change link | |
| Global scope | **World** | Breadcrumb root; replaces "All" |
| Geolocation filter | **Near me** | |
| Data freshness | **Updated {time}** | |

## Component Reuse Map

| Component | Used on | Behavior differences |
| --- | --- | --- |
| Layout (header, footer, dialogs) | All | — |
| Breadcrumbs | Country, Region, Resort | Region crumb omitted for small countries |
| Status line | Home, Country, Region | Count + scope + updated time; empty-state variant |
| Scope chips | Home, Country, Region | Near me hidden if geolocation unavailable/denied |
| Ranked resort list | Home (top 25), Country (top 25 or all), Region (all), Near-me (client) | Region: all columns sortable + per-day sort on desktop |
| Sub-area table | Home (countries), large Country (regions) | Same columns; different row entity |
| Snow value (cell/chip) | Lists, summary, strip, nearby, search results | Size variants: inline, cell, hero |
| 16-day strip | Resort (full), list rows (mini) | Mini: no axis/labels, `aria-label` only |
| Map | Home, Country, Region (overview); Resort (locator) | Overview: all dots in scope; locator: resort + nearby, fixed zoom |
| Nearby list | Resort | — |
| Details table | Resort (hourly, daily) | Hourly uses viewer TZ; daily uses resort-local days |
| Empty state | Home, Country, Region | Link target: snowiest sibling scope, then World |

## Content Growth Plan

Content is generated, not authored: resort count grows only via OpenSkiMap
scrapes (`rake scrape`). Scaling points:
- Lists cap at top 25 on Home and large Countries; sub-area tables carry the
  rest. Region pages list all (max 114 today; if any region exceeds ~150,
  cap at top 50 + "show all" rendered in `<details>`).
- Search index (390 KB today) grows with lat/lon + 7d snow; keep compact keys,
  round lat/lon to 3 decimals. Revisit (split per country) if it passes
  ~500 KB.
- `_redirects` grows with countries/regions; well under limit.
- Small-country threshold (≤20) stays the single switch; builder, search
  index, breadcrumbs and redirects must agree on it.

## URL Strategy

- Pattern: unchanged — `/countries/:country`, `/states/:region`,
  `/resorts/:resort`; slugs via Stringex `#to_url`.
- Dynamic segments: country, region, resort slugs (build-time fan-out).
- Query parameters:
  - `?sort=24h|past72h|7d|16d|YYYY-MM-DD` — list sort, reflected via
    `history.replaceState` so sorted views are shareable. Default `7d` omitted.
  - No query params for units/timezone (per-user prefs, localStorage).
  - "Near me" not encoded in URL (location is private).
- Canonical: every page sets `<link rel="canonical">` to its path without
  query.
- Retired: `*-snow-now` paths → 301 to parent scope.
