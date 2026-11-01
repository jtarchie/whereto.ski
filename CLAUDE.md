# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

Ruby static site generator for https://whereto.ski: loads ski resorts from
SQLite, fetches Open-Meteo forecasts per resort, renders ERB into `docs/`,
deployed to Cloudflare Pages.

Env: `OPEN_METEO_API_URL` (default `https://api.open-meteo.com`),
`OPEN_METEO_API_KEY` (paid tier; optional). `OPENWEATHER_API_KEY` in CI is
unused.

## Commands

Setup: `brew bundle && bundle install && npm install`. `data/features.sqlite` is
Git LFS — needs `git lfs pull` or nothing builds.

- `bundle exec rspec` — full suite (CI). Slow (~7 min): Capybara + headless
  Chrome.
- `bundle exec rspec spec/forecasts/daily_spec.rb:42` — single file/example.
- `rake assets` — Tailwind (`npm run build`) + esbuild →
  `pages/public/assets/main.{css,js}` (gitignored; build before browser specs or
  a fresh build).
- `rake fast` — full site build with stubbed weather (reuses `stub_weather_api`
  from `spec/spec_helper.rb`). No network, no `minify`.
- `rake build[limit]` — real build with live API, then `minify` (must be on
  PATH). `limit` = first N resorts.
- `rake fmt` — `deno fmt`, `rubocop -A`, Herb linter `--fix` + formatter on
  `pages/`.
- `rake a11y` — vnu + pa11y-ci against an existing `docs/` (run a build first).
- `rake scrape` — rebuild `features.sqlite` from OpenSkiMap.
- Preview: `ruby -run -ehttpd docs/ -p8000`.

CI (`ruby.yml`) runs rspec plus Herb lint (`--fail-level error`) and
`herb formatter --check` on `pages/`. `build.yml` builds daily and deploys;
`docs/` is gitignored, not committed (README is stale on this).

## Architecture

Pipeline: `Resort.from_sqlite` → `Builder::Site#build!` → `docs/`.

- **Routing by filename.** `Site#build!` globs `pages/**/*.html.erb` (skipping
  `_`-prefixed). Placeholders `[resort]`, `[state]`, `[country]` in filenames
  fan out one page per entity; slugs via Stringex `#to_url`. Add a page type =
  add a template with a placeholder and a `case` branch in `builder.rb`.
- **Render model.** Each template renders with `Builder::Context` as `self` plus
  locals (`resort`, `state`/`resorts`, `country`/`states`). Its output is parsed
  for HTML front matter, then wrapped in `_layout.html.erb` with front matter +
  `content` as locals. Helpers templates call (scoring, formatting, rankings,
  snow totals) live in `builder/context.rb` — add template helpers there.
- **Forecasts are lazy.** `Resort#forecasts` memoizes a `Forecast::OpenMeteo`
  client; first template access triggers the HTTP call. Daily data is passed
  through aggregator classes (`Forecast::Daily`) chained via `reduce`. So
  rendering = network I/O.
- **Rate limiting.** Resort pages render in parallel (50 threads) behind
  `Limiter::RateQueue` (50 / 10s, half Open-Meteo's limit); limiter is skipped
  when `RSpec` is defined. Resorts render first so state/country pages hit
  memoized forecasts.
- **Small countries** (`Context#small_country?`) get no state pages and no state
  entries in the search index — keep the builder and search index in agreement.
- **Search index** `docs/assets/search-data.json` uses compact keys (`t` type
  c/s/r, `n`, `u`, `c` = index into `cl` country list, `s`); `pages/input.js`
  consumes it.
- **Specs** share one full-site build per suite (`SharedBuild.perform!` in
  `spec_helper.rb`) against the real SQLite DB with WebMock-stubbed Open-Meteo;
  Capybara serves the tmp build dir. `.rspec` auto-requires `spec_helper`.

## Conventions

- `# frozen_string_literal: true` on every Ruby file.
- No Ruby 3.1 hash shorthand: write `resort: resort`, not `resort:`
  (`Style/HashSyntax: EnforcedShorthandSyntax: never`).
- `Layout/ExtraSpacing: ForceEqualSignAlignment` — consecutive assignments get
  their `=` aligned; `rubocop -A` fixes it. Metrics cops are off.
- ERB is linted/formatted by Herb (`.herb.yml`); run `rake fmt` before
  committing template changes.
