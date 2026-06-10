# TASK: Build "AusNow" — an auto-updating Australian GDP nowcasting web tool

## Mission

Build a fully automated GDP nowcasting system for Australia, in the spirit of the
Atlanta Fed's GDPNow: a running estimate of quarterly real GDP growth (q/q, seasonally
adjusted, chain volume — matching the ABS 5206.0 headline) for every quarter that has
ended or begun but not yet been published. At most times this means two live targets:
the **completed-but-unreleased quarter** and the **current quarter**.

The defining feature is **release-by-release tracking**: every time a relevant public
data release lands, the system updates the nowcast and records exactly how much that
release moved the estimate. The website's centrepiece is the GDPNow-style evolution
chart: nowcast on the y-axis, release dates on the x-axis, with a table attributing
each movement to the release that caused it.

Work autonomously. Do not stop to ask questions. Make defensible decisions, log them in
`docs/DECISIONS.md` (issue / options considered / decision / consequence / reversible,
severity LOW–MEDIUM–HIGH), and keep going. The system must run end-to-end without human
intervention once deployed — with one deliberate exception: a manual drop folder for the
NAB business survey, described below.

## Architecture (fixed — do not redesign)

- **Modelling**: R. Data via `readabs` and `readrba`; anything else by direct CSV/API
  download with no credentials required.
- **Scheduler**: GitHub Actions. A scheduled workflow runs every weekday shortly after
  the ABS 11:30am AEST release window (remember GitHub cron is **UTC** — schedule
  ~01:45 UTC, and handle AEST/AEDT drift by just running daily at a time that is safely
  after 11:30am Sydney year-round; also support `workflow_dispatch` for manual runs,
  and trigger a run on push to the manual drop folder so a NAB upload updates the
  nowcast immediately).
- **State**: the repo itself is the database. Every run commits: (a) a vintage snapshot
  of all input series (parquet or rds, one folder per run date), (b) an appended row per
  target quarter in `data/nowcast_history.csv` (run date, target quarter, headline
  estimate, labour-read estimate, expenditure estimate, blend weight, component
  contributions), (c) an appended row per detected release in
  `data/release_impacts.csv` (release name, series IDs, publication date, old estimate,
  new estimate, impact, affected component).
- **Manual input**: `data/manual/nab/` is a drop folder. Once a month a human will
  place the NAB business survey file there (assume xlsx or similar; whatever NAB
  currently distributes). The pipeline ingests whatever it finds, is robust to the
  folder being empty or the latest file being stale, and never fails because of it —
  if the most recent NAB observation is older than ~45 days, the model runs without it
  and the site shows "NAB survey: awaiting this month's file". Write the parser
  defensively (sheet/column discovery by header matching, not hard-coded cell
  references) and log the format assumptions you make. Treat a new NAB file exactly
  like any other data release: detect it, attribute its impact, record it.
- **Frontend**: a static site (single self-contained HTML page, vanilla JS + a charting
  lib loaded from CDN) rebuilt by the workflow from the CSVs and deployed to
  **GitHub Pages**. No server, no build framework heavier than necessary.
- **Repo layout**: `R/` (functions), `scripts/` (pipeline steps), `data/` (state and
  `data/manual/nab/`), `site/` (generated), `.github/workflows/nowcast.yml`, `docs/`
  (methodology, decisions, data dictionary), `tests/`.

## Phase 0 — Indicator inventory (verify, don't assume)

Build the indicator set from what the ABS **currently publishes** — release programs
change (e.g. the retail trade survey's replacement by the Monthly Household Spending
Indicator; changes to payroll-jobs publications). Scrape or fetch the ABS release
calendar and confirm, for every candidate indicator: catalogue/series IDs, frequency,
typical publication lag, and next scheduled dates. Record all of it in
`docs/data_dictionary.md`.

Candidate set to investigate (extend as you see fit):

- **Labour market (a first-class GDP input here, not a side project)**: monthly labour
  force survey — above all **aggregate hours worked**, plus employment and
  participation; quarterly job vacancies; ATO payroll-jobs-based indicators if
  currently published. The LFS is monthly, timely, and covers the quarter fully well
  before any quarterly expenditure partial — it is the backbone of the early read
  described in Phase 1.
- **GDP expenditure partials**: monthly household spending indicator; building
  approvals and construction work done; private new capital expenditure (capex survey);
  business indicators (inventories, company profits); international trade in goods
  (monthly); balance of payments and government finance statistics (the quarter's
  authoritative partials, released in the days immediately before GDP — the nowcast
  must keep updating through this "partials week"); retail trade volumes if still
  published.
- **Prices/deflator-adjacent**: monthly CPI; WPI (for nominal-to-real handling where
  needed).
- **Survey/sentiment**: the NAB business survey via the manual drop folder (business
  conditions, trading, employment, capacity utilisation — test which subindices earn
  their keep); Westpac–MI consumer sentiment and PMIs only if freely and reliably
  machine-readable, otherwise log the exclusion.
- **RBA/financial**: cash rate, credit aggregates — likely low value but cheap to test.

Rule: every automated indicator must be (1) free, (2) fetchable headlessly without
credentials, (3) on a known release schedule. The NAB drop folder is the sole sanctioned
exception. Anything else failing these is out, with a decision-log entry.

## Phase 1 — Methodology

The nowcast is a **blend of two semi-independent reads** on the same quarter, and the
site shows both alongside the blended headline:

**Read 1 — the labour read (good initial signal, available early).** GDP ≈ aggregate
hours worked × labour productivity. Hours worked for all three months of the quarter is
known shortly after quarter end (and two of three months well before that), long ahead
of the expenditure partials. Model quarterly GDP growth as hours growth plus a
productivity-trend term (estimate the productivity component — slow-moving trend with
cyclical adjustment, e.g. using capacity utilisation from NAB when available; keep it
simple and honest, productivity is the noisy residual here and the backtest will show
it). This read exists to anchor the nowcast early in the cycle when the expenditure
side is still mostly model-filled. It is explicitly a *good initial read, not the best
read* — its blend weight must decay as hard expenditure data accumulates.

**Read 2 — the expenditure read (bridge-equation, bottom-up; converges to the truth).**
Mirror the GDPNow design:

1. Decompose target GDP growth into expenditure components (household consumption,
   dwelling investment, new business investment, public consumption, public investment,
   inventories contribution, exports, imports — match the ABS 5206.0 expenditure
   aggregates).
2. For each component, estimate a **bridge equation** mapping available monthly/
   quarterly partials onto the component's quarterly growth. Where no partial exists or
   months are missing, fill with auxiliary models (AR, or factor-augmented AR) so every
   component always has a model-consistent estimate regardless of the data ragged edge.
3. Aggregate bottom-up with current ABS weights.

**Blending.** Combine the two reads with weights estimated from the backtest as a
function of position in the release cycle (days since quarter start / days until GDP
release). Expected shape — verify rather than impose: labour-read-heavy early,
expenditure-read-dominant by partials week. Publish the weight path in
`docs/methodology.md` and show the current weight on the site. When the quarter has no
in-quarter data at all yet, the estimate is model-only — badge it as such.

**Release attribution (the core feature).** When a run detects new data: compute the
blended nowcast with the new release included and with it excluded (previous vintage),
holding everything else fixed. The difference is that release's impact. If multiple
releases land the same day, attribute sequentially in publication-time order and log
each separately. Revisions to previously-published data count as "releases" too and get
attributed the same way. A new NAB file in the drop folder is a release like any other.
Persist every attribution to `data/release_impacts.csv`.

**Backtesting (mandatory before the site goes live).** Pseudo-real-time evaluation:
walk forward over at least the last 8–10 years, re-estimating bridge equations,
productivity terms, and blend weights on expanding windows and reconstructing what the
nowcast would have said at each point in the release cycle (true data vintages are
mostly unavailable for Australia — use current vintages and log this limitation
honestly as MEDIUM). Report, in `docs/methodology.md`: RMSE by days-until-release for
the labour read, the expenditure read, and the blend, versus two benchmarks — a naive
AR(1) and the historical mean. The blend must beat the AR benchmark in the final weeks
before release and should beat either read alone for at least part of the cycle; if a
component model or indicator doesn't earn its keep, simplify it out and log why.

## Phase 2 — Pipeline

`scripts/run_nowcast.R`, orchestrated as: fetch all series and scan the NAB drop folder
→ diff against the last vintage snapshot to detect what's new → if nothing new, exit
cleanly without committing noise (but record a heartbeat) → re-estimate/update →
compute attributions → append state CSVs → rebuild site → commit. Idempotent:
re-running on the same day must not duplicate rows. Robust: a single failed download
must not kill the run — degrade to the prior vintage for that series, flag it on the
site ("stale: series X as of date Y"), and log it. All errors trapped; the workflow
itself must virtually never red-X on data problems, only on genuine code defects.

Quarter rollover logic: when ABS publishes GDP for quarter Q, the system records the
final nowcast error for Q (for both reads and the blend), retires Q to the archive,
promotes Q+1 to "completed-unreleased" when the calendar says so, and opens Q+2 as
"current". This state machine must be explicit, tested, and correct across year
boundaries.

## Phase 3 — The website

Single clean page. Required elements, in priority order:

1. **Headline numbers**: blended nowcast for each live target quarter, with
   last-updated timestamp (Sydney time) and the change since the previous run; the
   labour read and expenditure read shown as secondary figures beneath, with the
   current blend weight.
2. **Evolution chart** per target quarter: blended nowcast path over the release cycle,
   x = date, with the labour and expenditure reads as lighter companion lines;
   hoverable points showing which release(s) moved the estimate and by how much.
   Include the eventual ABS outcome as a marked horizontal line once published (retired
   quarters viewable in an archive selector).
3. **Release table**: reverse-chronological — date, release, component affected, impact
   in pp on the blended nowcast (▲/▼), running estimate after.
4. **Component contribution bar**: stacked contributions to q/q growth from the
   expenditure read (consumption, investment, public, inventories, net exports).
5. **Upcoming releases** strip: next 5 scheduled releases that will feed the model,
   plus the NAB drop-folder status ("received for May" / "awaiting June file").
6. A short methodology note linked to `docs/methodology.md`, including the backtest
   accuracy chart, and an honest uncertainty band (from backtest errors, varying with
   position in the release cycle) on every headline number.

Design: restrained, financial-research aesthetic — it will be read by economists.
Charts must be legible on mobile. No frameworks requiring a build step.

## Phase 4 — Hardening and handover

- `tests/`: state-machine rollover tests, attribution arithmetic tests (impacts must
  sum to total change between runs), idempotency test, fetch-failure degradation test,
  NAB-folder tests (empty folder, stale file, malformed file, new file detected and
  attributed).
- Run the full pipeline locally at least three times on consecutive simulated "days"
  (mock the date) and verify history accrues correctly, including a simulated NAB drop.
- Verify the GitHub Actions workflow end-to-end, including the Pages deploy and the
  push-trigger on the drop folder. The workflow needs `contents: write` permission to
  commit state — set this up properly.
- `README.md`: what it is, how it updates, how to read the charts, **exactly how to
  drop the monthly NAB file in** (filename conventions, where, what happens next), how
  to run locally, and how to add a new indicator (a ~20-line recipe, not surgery).

## Definition of done

1. A scheduled GitHub Actions run completes green, commits new state, and the Pages
   site reflects it — demonstrated, not assumed.
2. Evolution chart and release-attribution table work, attributions sum exactly to
   estimate changes, and both reads plus the blend are visible and archived.
3. Dropping a file into `data/manual/nab/` triggers an update and shows up as an
   attributed release.
4. Backtest results documented; the blend beats the AR benchmark late-cycle and the
   weight path is published.
5. A failed/missing data source (including an absent NAB file) degrades gracefully and
   visibly, never fatally.
6. `docs/DECISIONS.md`, `docs/methodology.md`, `docs/data_dictionary.md` complete.
7. All tests pass; pipeline is idempotent.

Begin with Phase 0. Verify the live ABS release program before designing anything.
