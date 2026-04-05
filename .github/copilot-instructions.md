# Copilot Instructions — Follow the Snow

Trust these instructions. Only search the codebase if something here is incomplete or appears incorrect.

## What This Repository Does

A Ruby static site generator that fetches ski resort snow forecasts from the Open-Meteo API, stores resort data in SQLite, renders ERB templates into HTML pages, and deploys the site to Cloudflare Pages. Live at https://whereto.ski.

## Languages, Frameworks, Runtimes

- **Ruby 4.0** (`.ruby-version`), YJIT enabled in CI (`RUBY_YJIT_ENABLE=1`)
- **Node.js 24** — Tailwind CSS 4, DaisyUI, esbuild (frontend assets only)
- **SQLite3** — resort/geographic data in `data/features.sqlite` (14.5 MB, tracked via Git LFS)
- **RSpec** — testing; **RuboCop** — linting; **Deno** — JS/JSON formatting
- **Tilt/ERB** — templating; **Rake** — task runner

## Bootstrap (run in this exact order)

```bash
brew bundle            # macOS only: installs ruby, node, minify, deno, direnv
bundle install         # Always run after cloning or pulling; installs Ruby gems
npm install            # Always run after bundle install; installs Tailwind/esbuild
```

On Linux (CI), `minify` v2.24.8 is installed from GitHub releases — it is **only required for `rake build`**, not for tests.

## Build Commands (validated)

| Command | Purpose | Notes |
|---|---|---|
| `bundle exec rspec` | Run tests | CI command; ~7 min (216 examples, headless Chrome); requires `npm install` already run |
| `rake test` | Run tests (also builds assets first) | Slower than `bundle exec rspec` |
| `rake assets` | Build CSS and JS | Always run before `rake fast` or `rake build` if assets changed |
| `rake fmt` | Format all code | Runs: `deno fmt .`, `rubocop -A`, `herb analyze pages/`, `npx @herb-tools/formatter pages/` |
| `rake fast` | Quick build with mock API data | Depends on `rake assets`; no `minify` needed; ~60–90s |
| `rake build` | Production build with live weather data | Depends on `rake assets`; requires `minify` in PATH |
| `rake default` | Runs `fast`, `fmt`, `test` in sequence | Good pre-commit check |

**Note:** `rake css` does **not** exist. The correct task is `rake assets`.

## CI Pipeline (`.github/workflows/ruby.yml`)

Triggers on push/PR to `main`. Steps:
1. `actions/checkout@v4` with `lfs: true` (required — SQLite file is in Git LFS)
2. `ruby/setup-ruby@v1` with `ruby-version: "4.0"` and `bundler-cache: true`
3. `bundle exec rspec`

**To replicate CI locally:**
```bash
bundle install && bundle exec rspec
```

Warnings like `Source locally installed gems is ignoring ... because it is missing extensions` are harmless noise from Ruby 4.0 native extension compilation — ignore them.

## Project Layout

```
lib/follow_the_snow/
  follow_the_snow.rb   # Module entry point
  resort.rb            # Resort struct; from_sqlite() loader; forecast delegation
  builder.rb           # Site.build!() — main orchestration (parallel, rate-limited)
  forecast.rb          # Forecast / HourlyForecast / CurrentConditions structs
  openskimap.rb        # Builds features.sqlite from OpenSkiMap GeoJSON
  builder/
    context.rb         # Template helper methods (ski scoring, formatting, rankings)
    snow_helper.rb     # Snow calculation helpers
  forecasts/
    open_meteo.rb      # Open-Meteo API client
    daily.rb           # Daily forecast aggregation

pages/                 # ERB templates (rendered to docs/)
  _layout.html.erb     # Main layout
  index.html.erb       # Home page
  [country].html.erb   # Generated per-country pages (in pages/countries/)
  [state].html.erb     # Generated per-state/region pages (in pages/states/)
  [resort].html.erb    # Generated per-resort pages (in pages/resorts/)
  input.css            # Tailwind CSS entry point
  input.js             # Frontend JS entry point
  public/assets/       # Built CSS (main.css) and JS (main.js)

spec/
  spec_helper.rb       # WebMock + Capybara setup; defines stub_weather_api()
  build_spec.rb        # Core build tests (757 lines)
  *.spec_rb            # Other feature specs

data/
  features.sqlite      # Resort/geo database (Git LFS, 14.5 MB)
  countries/           # countries.csv, subdivisions.csv

.github/workflows/
  ruby.yml             # Test on push/PR → bundle exec rspec
  build.yml            # Daily build at 10:00 UTC → rake build → Cloudflare deploy

.rubocop.yml           # RuboCop config: Ruby 4.0, plugins: rubocop-rspec, rubocop-rake
package.json           # Node scripts: "build" = tailwind CLI → main.css
```

## Ruby Conventions

- Always add `# frozen_string_literal: true` at the top of every Ruby file
- **Hash syntax**: use classic rockets (`key => value`), not shorthand — this is enforced by `.rubocop.yml` (`Style/HashSyntax: EnforcedShorthandSyntax: never`)
- Metrics cops (MethodLength, ClassLength, BlockLength, LineLength, AbcSize) are **disabled** — don't worry about them
- Module/class nesting style is flexible (`Style/ClassAndModuleChildren` is disabled)

## Testing Conventions

- Test files in `spec/` mirror `lib/` structure
- Always `require 'spec_helper'` at the top of spec files
- Use `stub_weather_api` (defined in `spec_helper.rb`) to mock Open-Meteo responses
- HTTP is mocked via WebMock; no real API calls in tests
- Capybara + headless Chrome used for UI tests

## Environment Variables

- `OPEN_METEO_API_URL` — optional custom endpoint (default: public Open-Meteo)
- `OPEN_METEO_API_KEY` — optional API key for paid Open-Meteo tier
- `OPENWEATHER_API_KEY` — present in CI secrets but **currently unused**
