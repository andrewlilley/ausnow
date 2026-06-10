# AusNow — an auto-updating Australian GDP nowcast

A fully automated nowcast of Australian quarterly real GDP growth (q/q, seasonally
adjusted, chain volume — the ABS 5206.0 headline), in the spirit of the Atlanta Fed's
GDPNow. Every weekday after the ABS 11:30am (Sydney) release window, a GitHub Actions
run fetches the latest data, updates the estimate for every unpublished quarter, and
records **exactly how much each data release moved the nowcast**. A static site on
GitHub Pages shows the running estimate, its evolution chart, and the full release
attribution table.

## How it works (one paragraph)

Two semi-independent reads are blended: a **labour read** (hours worked × trend
productivity — available within weeks of quarter end) and an **expenditure read**
(bridge equations mapping ABS partials — household spending, approvals, capex, trade,
inventories, BoP, GFS — onto each GDP(E) component, aggregated bottom-up). The blend
weight slides from labour-heavy early in the cycle to expenditure-dominant by
"partials week", on a path estimated by a 10-year pseudo-real-time backtest. Details:
[docs/methodology.md](docs/methodology.md); indicator inventory:
[docs/data_dictionary.md](docs/data_dictionary.md); design decisions:
[docs/DECISIONS.md](docs/DECISIONS.md).

## How it updates

- `.github/workflows/nowcast.yml` runs weekdays at 02:05 UTC (after 11:30am Sydney
  year-round), on manual dispatch, and on any push to `data/manual/nab/`.
- The repo is the database. Each run commits: a vintage snapshot
  (`data/vintages/YYYY-MM-DD/`), an appended row per live target quarter in
  `data/nowcast_history.csv`, one row per detected release in
  `data/release_impacts.csv`, and the rebuilt `site/index.html`.
- No new data ⇒ a heartbeat row in `data/heartbeat.csv` and no noise commits.
- A failed download never kills the run: the pipeline degrades to the previous
  vintage for that series and the site shows a "stale" warning chip.

## Reading the charts

- **Headline cards** — the blended nowcast per live quarter, with an 80% band from
  backtest errors, the change since the previous run, both reads, and the current
  blend weight. "Model-only" badge = no in-quarter hard data yet.
- **Evolution chart** — the nowcast path across the release cycle; hover any point to
  see which release(s) moved it and by how much. The green line marks the eventual
  ABS outcome once published; retired quarters live in the archive selector.
- **Release table** — reverse-chronological attribution: ▲/▼ impact in percentage
  points per release, and the running estimate after each.

## Dropping in the monthly NAB file (the one manual step)

1. Get the monthly NAB business survey data file (xlsx, xls or csv — whatever NAB
   distributes; a data table with a date column and named index columns).
2. Drop it into **`data/manual/nab/`** — any filename, e.g.
   `nab-survey-2026-06.xlsx`. Don't delete old files; newer files override
   overlapping months.
3. Commit and push (or use the GitHub web UI: *Add file → Upload files* into
   `data/manual/nab/`). The push itself triggers a nowcast run; the new survey is
   detected, parsed by header matching (it looks for "business conditions",
   "business confidence", "capacity utilisation", "trading", "employment"), and shows
   up in the release table as "NAB Business Survey" with its measured impact.
4. If the folder is empty or the latest file is older than ~45 days, the model simply
   runs without NAB and the site shows "NAB survey: awaiting this month's file".
   Nothing breaks.

## Running locally

```sh
# R >= 4.2 with: readabs readrba dplyr tidyr readxl jsonlite testthat zoo purrr stringr
Rscript tests/run_tests.R          # hermetic test suite (no network)
Rscript scripts/run_nowcast.R      # full pipeline run (fetches ABS/RBA data)
Rscript scripts/backtest.R         # regenerate backtest, weights, bands (~1h)
open site/index.html
```

`AUSNOW_TODAY=2026-06-11 Rscript scripts/run_nowcast.R` simulates a run date —
that's all the 3-day simulation in `tests/simulate_3day.R` does.

## Adding a new indicator (the ~20-line recipe)

1. **Register the fetch** — add an entry to `INDICATORS` in `R/config.R`:
   ```r
   mything = list(label = "My Indicator, ABS XXXX.0",
                  fetch = list(type = "abs_ts", cat_no = "XXXX.0", tables = "1"),
                  freq = "M", pub_lag_days = 35, component = "hfce")
   ```
   (types: `abs_ts`, `abs_series`, `abs_cube`, `rba_table`, `nab_folder`.)
2. **Name the series** — add to `SERIES`:
   `mything_total = list(key = "mything", id = "A1234567X")`.
3. **Feed a bridge** — in `R/models.R`, add a regressor line in `build_qframe()`
   (e.g. `add("x_mything", m_growth("mything_total"))`) and append `"x_mything"` to
   the relevant component's regressor list in `BRIDGES`.
4. **Name the release** — add a display name in `RELEASE_NAMES` (`R/config.R`).
5. Run `Rscript scripts/backtest.R`. If the new indicator doesn't lower RMSE, take it
   back out and log why in `docs/DECISIONS.md`.

## Repo layout

```
R/          functions (config, fetch, models, attribution, state, site, nab, calendar)
scripts/    run_nowcast.R (daily pipeline), backtest.R
data/       state CSVs, vintage snapshots, manual/nab/ drop folder
site/       template.html (source) -> index.html (generated, deployed to Pages)
docs/       methodology, data dictionary, decision log, backtest results
tests/      hermetic testthat suite + 3-day simulation
```

All estimates are model output, not official statistics. Source data: ABS, RBA, NAB.
