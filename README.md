# whereto.ski

Static site ranking ski resorts by incoming snow: <https://whereto.ski>.

- **Resorts:** OpenSkiMap, scraped with `rake scrape` into
  `data/features.sqlite` (Git LFS; needs `git lfs pull`).
- **Forecasts:** [Open-Meteo](https://open-meteo.com), fetched per resort at
  build time.
- **Build/deploy:** Ruby generator renders ERB from `pages/` into `docs/`.
  GitHub Actions (`.github/workflows/build.yml`) builds daily and deploys to
  Cloudflare Pages.

Setup, commands, architecture and conventions: see [CLAUDE.md](CLAUDE.md).
