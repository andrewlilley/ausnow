# Decision log

Format: issue / options / decision / consequence / reversible? / severity.

---

**D1. Vintage snapshot format: rds, not parquet.**
Options: parquet (arrow) vs rds. The runner has no `arrow` installed and arrow adds a
heavy compiled dependency to CI. rds is native, stable, and snapshots are only read by
this R pipeline. Consequence: snapshots not directly readable outside R (CSV state
files remain the public interface). Reversible: yes, trivially. **LOW**

**D2. LFS access path.** `read_abs("6202.0", tables=...)` fails through the Time
Series Directory for several 6202 tables on readabs 0.4.30 (table renumbering), but
table 17 (hours) works and `read_abs_series()` works for employment/participation.
Decision: hours via table 17, employment/participation via direct series IDs.
Consequence: if the ABS renumbers again, the fetch degrades gracefully (stale flag)
rather than failing. Reversible: yes. **LOW**

**D3. Payroll jobs excluded.** The weekly-payroll-jobs-and-wages catalogue no longer
exists on the ABS website (verified 2026-06-10: `get_available_files` returns "No
matching catalogue", no SDMX dataflow). The publication has been discontinued.
Hours worked from the LFS carries the same signal for the labour read. Reversible:
yes, add back if the ABS revives an admin-data jobs indicator. **LOW**

**D4. MHSI is current-price only.** The Monthly Household Spending Indicator has no
volume measure. Decision: deflate the monthly MHSI by the monthly all-groups CPI to
get a real-spending proxy for the household consumption bridge, and let the bridge
regression absorb residual deflator mismatch. Consequence: deflator noise in the
consumption bridge, visible in backtest RMSE. Reversible: yes. **MEDIUM**

**D5. Monthly trade is nominal and goods-only.** The monthly 5368.0 release covers
goods on a current-price basis; volumes and services arrive only with the quarterly
BoP in partials week. Decision: bridge real export/import growth on nominal goods
growth early in the cycle (commodity-price noise accepted), switch weight to BoP CVM
when published. The backtest quantifies how much the nominal bridge helps vs an AR
fill. Reversible: yes. **MEDIUM**

**D6. Public demand bridge.** GFS quarterly (5519.0.55.001) is a data cube whose
filename changes each quarter. Decision: discover the cube via `get_available_files`
each run and parse by header matching; GFS lands one day before GDP so its main role
is the final partials-week update; before that public components are AR-filled.
Consequence: small accuracy gain limited to the last two days of the cycle.
Reversible: yes. **LOW**

**D7. Building approvals counts only.** The 2025 revamp of 8731.0 dropped value
series from the time-series tables; counts of dwellings approved remain. Decision:
use total dwellings approved (lagged) plus quarterly building work done for the
dwelling investment bridge. **LOW**

**D8. Pseudo-real-time backtest uses current vintages.** True historical vintages for
most ABS monthly indicators are not freely available. The backtest reconstructs the
data *availability pattern* (what had been published by each pseudo run date, using
each series' publication lag) but uses final/current values, which flatters bridge
fits somewhat relative to genuine real-time operation. Logged honestly in
methodology.md. Not reversible without a vintage archive (which this system now
builds going forward). **MEDIUM**

**D9. Survey exclusions.** Westpac–MI consumer sentiment and S&P Global PMIs are not
machine-readable from a stable free URL without credentials/scraping fragile press
pages. Excluded under the free/headless rule; NAB enters via the sanctioned manual
drop folder. Reversible: yes. **LOW**

**D10. Charting library: ECharts via CDN.** Options: Chart.js (light, weaker
financial defaults), Plotly (heavy ~3.5 MB), ECharts (~1 MB, good mobile + hover).
Decision: ECharts 5 from jsDelivr CDN, single self-contained `index.html`, data
inlined as JSON at build time so the page works with no server and no CORS issues.
Reversible: yes. **LOW**

**D11. Quarterly state files keyed by (run_date, target_quarter).** Idempotency rule:
a re-run on the same date for the same target replaces (not appends) that key in
`nowcast_history.csv`; `release_impacts.csv` is keyed by (publication_date, release,
target_quarter) likewise. Consequence: same-day re-runs are clean no-ops unless new
data arrived. **LOW**

**D12. Company profits excluded from bridges** (weak marginal GDP(E) predictor;
inventories are the partials-week signal from 5676.0). RBA cash rate and credit kept
as cheap candidate regressors and dropped in backtest if they don't earn their keep.
**LOW**

**D13. Two-pillar blend, weights by days-until-release.** Blend weight on the labour
read estimated on a logistic decay in days-until-GDP-release, fit on backtest errors
(inverse-MSE weighting smoothed across the cycle), floored at 0.05/capped at 0.95 to
avoid degenerate corner solutions in small samples. Published in methodology.md.
**MEDIUM**

**D14. GitHub cron at 02:05 UTC weekdays.** 11:30 Sydney is 01:30 UTC in winter
(AEST) and 00:30 UTC in summer (AEDT); 02:05 UTC is safely after the release window
year-round, allowing for GitHub's cron jitter. Plus `workflow_dispatch` and a push
trigger on `data/manual/nab/**`. **LOW**
