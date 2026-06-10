# AusNow data dictionary

All sources verified live on 2026-06-10 by direct download. Every automated source is
free, headless, and credential-free. The sole manual input is the NAB business survey
drop folder (`data/manual/nab/`).

## Target

| Item | Detail |
|---|---|
| Target variable | Real GDP, chain volume measures, seasonally adjusted, q/q % growth |
| Source of truth | ABS 5206.0 Table 1, series `A2304402X` (level), `A2304370T` (% change) |
| Release schedule | Quarterly, ~9 weeks after quarter end: first Wednesday of March, June, September, December, 11:30am Sydney |
| Verified | Latest obs 2026 Q1 (published 2026-06-03) |

## Automated indicators

### ABS time series (fetched with `readabs::read_abs`, Time Series Directory)

| Key | Catalogue / table | Series (seasonally adjusted unless noted) | Freq | Typical lag | Feeds |
|---|---|---|---|---|---|
| `natacc` | 5206.0 t1, t2 | GDP CVM `A2304402X`; component CVM levels and contributions (see component map below) | Q | ~63 days | target, weights, rollover |
| `hours` | 6202.0 t17 | Monthly hours worked in all jobs, persons `A84426277X` | M | ~14 days | labour read |
| `lfs` | 6202.0 (direct series fetch) | Employed total `A84423043C`, participation rate `A84423050A` | M | ~14 days | labour read aux |
| `mhsi` | 5682.0 (Monthly Household Spending Indicator) | Total `A130200584T`, goods `A130200746W`, services `A130200608X` — **current price only** | M | ~35 days | household consumption bridge |
| `trade` | 5368.0 t1 | Goods credits `A2718577A`, goods debits `A2718603V` (current price; monthly release is goods only) | M | ~35 days | exports / imports bridges |
| `approvals` | 8731.0 t6 | Total dwelling units approved, total sectors `A422070J`; private houses `A418371K` (2025 revamp dropped value series — counts only) | M | ~35 days | dwelling investment bridge |
| `construction` | 8755.0 t1 | Work done CVM: total building `A405136V`, engineering `A405154X`, private total `A405118R` | Q | ~56 days | dwellings + business investment bridges |
| `capex` | 5625.0 t7 | Actual capex CVM: total `A124797537K`, equipment `A124797536J`, buildings & structures `A124797535F` | Q | ~60 days | business investment bridge |
| `busind` | 5676.0 t1 | Inventories CVM, all industries `A3538852F` | Q | ~61 days (partials week) | inventories contribution |
| `bop` | 5302.0 t5 | CVM credits `A3535542V`, debits `A3535543W`; goods/services splits `A3535039K`/`A3535093X`/`A3535061F`/`A3535103T` | Q | ~62 days (partials week, day before GDP) | exports / imports (authoritative) |
| `cpi` | 6401.0 t1 | All groups CPI Australia `A130393720C` (monthly since Nov 2025; the old Monthly CPI Indicator 6484.0 stopped at Sep 2025) | M | ~25 days | deflating nominal partials |
| `vacancies` | 6354.0 t1 | Job vacancies Australia `A590698F` | Q | ~70 days | labour read aux |
| `wpi` | 6345.0 t1 | Total hourly rates of pay index `A2713849C` | Q | ~45 days | optional deflator |

### ABS data cubes (fetched with `readabs::download_abs_data_cube`)

| Key | Catalogue | Content | Freq | Lag | Feeds |
|---|---|---|---|---|---|
| `gfs` | 5519.0.55.001 Government Finance Statistics | National public sector: final consumption expenditure and gross fixed capital formation, current prices (cube filename changes each quarter, e.g. `Mar Quarter 2026.xlsx`; discovered at run time via `get_available_files`) | Q | ~62 days (released day before GDP) | public demand bridge |

### RBA (fetched with `readrba::read_rba`)

| Key | Table / series | Content | Freq | Feeds |
|---|---|---|---|---|
| `rba_cash` | `FIRMMCRTD` | Cash rate target (daily, averaged to monthly) | D | financial controls (tested in backtest) |
| `rba_credit` | Table D2 | Credit aggregates (business credit growth) | M | business investment aux (tested) |

### Manual drop folder

| Key | Path | Content | Freq |
|---|---|---|---|
| `nab` | `data/manual/nab/*.xls[x]` | NAB Monthly Business Survey: business conditions, business confidence, trading conditions, employment index, capacity utilisation. Parsed defensively by header matching (see `R/nab.R` and README). If the latest observation is older than 45 days the model runs without NAB and the site shows "awaiting this month's file". | M (manual) |

## Component map (expenditure read)

5206.0 Table 2, seasonally adjusted, chain volume measures:

| Component | CVM level | Contribution to growth | Bridge indicators |
|---|---|---|---|
| Household consumption | `A2304081W` | `A2303954C` | MHSI (CPI-deflated), NAB trading |
| Dwelling investment (incl. alterations) | `A2304098T` | `A2303988A` | approvals (lagged), building work done |
| Ownership transfer costs | `A2304099V` | `A2303990L` | AR |
| Private business investment | `A2304095K` | `A2303982L` | capex CVM, engineering work done, NAB capacity utilisation |
| Public consumption | `A2304080V` | `A2303952X` | GFS, AR |
| Public investment | `A2304109L` | `A2304008A` | GFS, AR |
| Change in inventories | `A2304112A` | `A2304020T` | business indicators inventories CVM |
| Exports | `A2304114F` | `A2304024A` | BoP CVM credits; monthly goods credits |
| Imports | `A2304115J` | `A2304026F` | BoP CVM debits; monthly goods debits |
| Statistical discrepancy | `A2304116K` | `A2304028K` | zero-mean AR |

## Release calendar

Upcoming dates are scraped each run from
`https://www.abs.gov.au/release-calendar/future-releases` (server-rendered HTML, rows
carry `<time datetime>` tags; parser in `R/calendar.R`). If the scrape fails the site
falls back to rule-based estimates (e.g. "GDP: first Wednesday of release month") and
flags the strip as estimated.

## Excluded indicators (see DECISIONS.md)

- **Retail trade (8501.0)** — discontinued by the ABS; superseded by the MHSI.
- **Payroll jobs** — the weekly-payroll-jobs catalogue no longer exists on the ABS
  site and no SDMX dataflow replaces it; hours worked already covers this signal.
- **Westpac–MI consumer sentiment, S&P PMIs** — not freely machine-readable on a
  stable URL without credentials; excluded under the free/headless rule.
- **Company profits (5676.0)** — weak marginal predictor for GDP(E); inventories are
  the partials-week signal from this release.
