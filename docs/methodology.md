# AusNow methodology

AusNow produces a running estimate ("nowcast") of Australian quarterly real GDP growth
(q/q, seasonally adjusted, chain volume measures — the ABS 5206.0 headline) for every
quarter that has begun or ended but not yet been published. It updates every weekday
after the ABS 11:30am release window and attributes every movement to the data release
that caused it, in the spirit of the Atlanta Fed's GDPNow.

## Two reads, one blend

### Read 1 — the labour read (early signal)

GDP ≈ aggregate hours worked × labour productivity, so q/q GDP growth is approximated
as

```
g_GDP ≈ g_hours + productivity trend (+ cyclical adjustment)
```

- **Hours**: monthly hours worked in all jobs (LFS 6202.0, seasonally adjusted),
  aggregated to a quarterly average. Missing months of the target quarter are filled
  with an AR(1) on m/m log growth; the site reports how many months are actually
  observed (0 observed months ⇒ the estimate is badged *model-only*).
- **Productivity trend**: the mean of (GDP growth − hours growth) over the last 20
  published quarters. This is deliberately simple: productivity is the noisy residual
  of this identity, and the backtest (below) shows exactly how much noise it
  contributes.
- **Cyclical adjustment**: when the NAB survey is available in the drop folder, the
  productivity residual is regressed on the quarterly change in NAB capacity
  utilisation and the fitted adjustment applied. Without NAB the term is zero.

The labour read exists because hours for all three months of the quarter are known
~2 weeks after quarter end — months before the expenditure partials are complete. It
is a good initial read, not the best read, and its blend weight decays accordingly.

### Read 2 — the expenditure read (bridge equations, bottom-up)

Target GDP growth is decomposed into the 5206.0 expenditure components. For each
component a **bridge equation** maps published partials onto the component's quarterly
growth:

| Component | Bridge regressors |
|---|---|
| Household consumption | Monthly Household Spending Indicator (CPI-deflated), NAB conditions |
| Dwelling investment | Building approvals (lagged one quarter), building work done |
| Ownership transfer costs | AR(1) |
| Business investment | Capex survey (CVM), engineering construction, NAB capacity utilisation |
| Public consumption / investment | Government Finance Statistics (quarterly, lands the day before GDP) |
| Inventories (contribution) | Second difference of Business Indicators inventories, scaled by GDP |
| Exports / imports | Quarterly BoP chain volume credits/debits; monthly nominal goods trade |
| Statistical discrepancy | Zero-mean AR |

Estimation: OLS on an expanding window (capped at 60 quarters, minimum 16
observations; below the minimum, or when a regressor is unavailable for the target
quarter, the component falls back to an AR(1) on its own growth). Monthly regressors
are aggregated to quarterly averages with AR(1)-filled ragged edges; quarterly
partials not yet published for the target quarter are AR(1)-forecast — so every
component always has a model-consistent estimate regardless of the data's ragged
edge.

Aggregation is bottom-up: components in growth-rate form are weighted by their
average chain-volume share of GDP over the last four published quarters (imports
negative); inventories and the statistical discrepancy enter directly as
contributions. Because chain-volume components do not add exactly, a bias-correction
constant (the mean bottom-up error over the last 12 published quarters) is added.

### The blend

```
nowcast = w(d) × labour read + (1 − w(d)) × expenditure read
```

where `d` is days until the scheduled GDP release. The weight path `w(d)` is
estimated from the backtest by inverse mean-squared-error at each point of the
release cycle, smoothed, and floored/capped at [0.05, 0.95] (DECISIONS.md D13). The
current weight is always shown on the site; the full path is in
`data/blend_weights.csv` and charted on the site.

## Release attribution

When a run detects new data (new observations *or revisions* — both count, and a new
NAB file in the drop folder is a release like any other), the changed sources are
swapped into the previous vintage one at a time in publication order, recomputing the
full blended nowcast after each swap. Each release's impact is the change it causes;
impacts sum exactly to the total movement between runs by construction. Every
attribution is persisted in `data/release_impacts.csv`.

## Quarter lifecycle

Live targets at any date are all quarters after the latest published GDP quarter up
to the quarter containing today — normally the completed-but-unreleased quarter and
the current quarter. When the ABS publishes GDP for quarter Q, the final nowcast
error for Q (both reads and the blend) is recorded in `data/final_errors.csv`, Q is
retired to the site archive, and the state machine promotes the next quarters. GDP
release dates follow the ABS pattern (first Wednesday of March/June/September/
December), cross-checked against the scraped ABS release calendar.

## Backtest design

Pseudo-real-time evaluation over targets from 2016Q1: for each target quarter and
each of 10 points in the release cycle (150 down to 1 days before release), the
dataset is truncated to what had been published by that date (using each series'
publication lag, and the exact release-date rule for national accounts), all bridges
and the productivity trend are re-estimated on the truncated sample, and both reads
are recorded against the eventual outcome, alongside two benchmarks: an AR(1) on
published GDP growth and the historical mean.

**Honest limitations** (DECISIONS.md D8): true historical vintages are mostly
unavailable for Australia, so the backtest uses *current* vintages with historically
accurate availability patterns. This flatters bridge fits somewhat relative to
genuine real-time operation (revisions are absent). The MHSI series history predates
the publication's launch; its early "availability" is therefore approximate. NAB
survey history accumulates in the drop folder only from deployment, so the backtest
runs without NAB terms. The vintage archive this system builds going forward will
allow a genuine real-time evaluation in time. The blend-weight path is estimated on
the full sample; the out-of-sample table below (targets 2022Q1+) is the honest check
that the blend's advantage is not a weight-fitting artefact.

Uncertainty bands shown on the site are ±1.28 × backtest RMSE of the blend at the
matching point in the release cycle (≈80% interval), linearly interpolated.

## Backtest results

See [backtest_results.md](backtest_results.md) (regenerated whenever
`scripts/backtest.R` runs; summary CSVs in `data/backtest_summary.csv` and the site's
accuracy chart are built from the same numbers).
