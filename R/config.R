# Indicator registry and component map. Series IDs verified 2026-06-10
# (docs/data_dictionary.md). Selection at model time is by series_id.

INDICATORS <- list(
  natacc = list(
    label = "National Accounts (GDP), ABS 5206.0",
    fetch = list(type = "abs_ts", cat_no = "5206.0", tables = c("1", "2")),
    freq = "Q", pub_lag_days = 63, component = "all"
  ),
  hours = list(
    label = "Labour Force Survey (hours worked), ABS 6202.0",
    fetch = list(type = "abs_ts", cat_no = "6202.0", tables = "17"),
    freq = "M", pub_lag_days = 14, component = "labour"
  ),
  lfs = list(
    label = "Labour Force Survey (employment), ABS 6202.0",
    fetch = list(type = "abs_series", series_ids = c("A84423043C", "A84423050A")),
    freq = "M", pub_lag_days = 14, component = "labour"
  ),
  mhsi = list(
    label = "Monthly Household Spending Indicator, ABS 5682.0",
    fetch = list(type = "abs_ts", cat_no = "5682.0", tables = "1"),
    freq = "M", pub_lag_days = 35, component = "hfce"
  ),
  trade = list(
    label = "International Trade in Goods, ABS 5368.0",
    fetch = list(type = "abs_ts", cat_no = "5368.0", tables = "1"),
    freq = "M", pub_lag_days = 35, component = "trade"
  ),
  approvals = list(
    label = "Building Approvals, ABS 8731.0",
    fetch = list(type = "abs_ts", cat_no = "8731.0", tables = "6"),
    freq = "M", pub_lag_days = 35, component = "dwell"
  ),
  construction = list(
    label = "Construction Work Done, ABS 8755.0",
    fetch = list(type = "abs_ts", cat_no = "8755.0", tables = "1"),
    freq = "Q", pub_lag_days = 56, component = "dwell/businv"
  ),
  capex = list(
    label = "Private New Capital Expenditure, ABS 5625.0",
    fetch = list(type = "abs_ts", cat_no = "5625.0", tables = "7"),
    freq = "Q", pub_lag_days = 60, component = "businv"
  ),
  busind = list(
    label = "Business Indicators (inventories), ABS 5676.0",
    fetch = list(type = "abs_ts", cat_no = "5676.0", tables = "1"),
    freq = "Q", pub_lag_days = 61, component = "inventories"
  ),
  bop = list(
    label = "Balance of Payments, ABS 5302.0",
    fetch = list(type = "abs_ts", cat_no = "5302.0", tables = "5"),
    freq = "Q", pub_lag_days = 62, component = "trade"
  ),
  cpi = list(
    label = "Monthly CPI, ABS 6401.0",
    fetch = list(type = "abs_ts", cat_no = "6401.0", tables = "1"),
    freq = "M", pub_lag_days = 25, component = "deflator"
  ),
  cpi_old = list(
    label = "Monthly CPI Indicator (historical), ABS 6484.0",
    fetch = list(type = "abs_ts", cat_no = "6484.0", tables = "1"),
    freq = "M", pub_lag_days = 25, component = "deflator"  # discontinued Sep 2025; history only
  ),
  vacancies = list(
    label = "Job Vacancies, ABS 6354.0",
    fetch = list(type = "abs_ts", cat_no = "6354.0", tables = "1"),
    freq = "Q", pub_lag_days = 70, component = "labour"
  ),
  gfs = list(
    label = "Government Finance Statistics, ABS 5519.0.55.001",
    fetch = list(type = "abs_cube", cat_string = "government-finance-statistics-australia"),
    freq = "Q", pub_lag_days = 62, component = "public"
  ),
  rba_credit = list(
    label = "RBA credit aggregates (D2)",
    fetch = list(type = "rba_table", table_no = "d2"),
    freq = "M", pub_lag_days = 31, component = "businv"
  ),
  nab = list(
    label = "NAB Monthly Business Survey (manual drop)",
    fetch = list(type = "nab_folder", path = "data/manual/nab"),
    freq = "M", pub_lag_days = 14, component = "survey", stale_after_days = 45
  )
)

# Series used by the models, keyed for extraction from the fetched tables.
SERIES <- list(
  gdp_cvm        = list(key = "natacc", id = "A2304402X"),
  hfce_cvm       = list(key = "natacc", id = "A2304081W"),
  dwell_cvm      = list(key = "natacc", id = "A2304098T"),
  otc_cvm        = list(key = "natacc", id = "A2304099V"),
  businv_cvm     = list(key = "natacc", id = "A2304095K"),
  pubcons_cvm    = list(key = "natacc", id = "A2304080V"),
  pubinv_cvm     = list(key = "natacc", id = "A2304109L"),
  exports_cvm    = list(key = "natacc", id = "A2304114F"),
  imports_cvm    = list(key = "natacc", id = "A2304115J"),
  inv_contrib    = list(key = "natacc", id = "A2304020T"),
  disc_contrib   = list(key = "natacc", id = "A2304028K"),
  hours_idx      = list(key = "hours", id = "A84426277X"),
  employed       = list(key = "lfs", id = "A84423043C"),
  mhsi_total     = list(key = "mhsi", id = "A130200584T"),
  trade_credits  = list(key = "trade", id = "A2718577A"),
  trade_debits   = list(key = "trade", id = "A2718603V"),
  approvals_tot  = list(key = "approvals", id = "A422070J"),
  constr_bldg    = list(key = "construction", id = "A405136V"),
  constr_eng     = list(key = "construction", id = "A405154X"),
  capex_tot      = list(key = "capex", id = "A124797537K"),
  capex_eqp      = list(key = "capex", id = "A124797536J"),
  busind_inv     = list(key = "busind", id = "A3538852F"),
  bop_credits    = list(key = "bop", id = "A3535542V"),
  bop_debits     = list(key = "bop", id = "A3535543W"),
  cpi_all        = list(key = "cpi", id = "A130393720C"),
  cpi_old_all    = list(key = "cpi_old", id = "A128478317T"),
  vacancies_aus  = list(key = "vacancies", id = "A590698F"),
  # synthetic ids produced by the GFS and NAB parsers
  gfs_pubdem     = list(key = "gfs", id = "GFS_PUBDEM"),
  nab_conditions = list(key = "nab", id = "NAB_CONDITIONS"),
  nab_caputil    = list(key = "nab", id = "NAB_CAPUTIL")
)

# Expenditure components: how each enters the bottom-up sum.
# mode "level": contribution = weight (CVM share, imports negative) x growth.
# mode "contrib": modelled directly as a contribution to GDP growth (pp).
COMPONENTS <- list(
  hfce        = list(label = "Household consumption", mode = "level", level = "hfce_cvm"),
  dwell       = list(label = "Dwelling investment",   mode = "level", level = "dwell_cvm"),
  otc         = list(label = "Ownership transfer costs", mode = "level", level = "otc_cvm"),
  businv      = list(label = "Business investment",   mode = "level", level = "businv_cvm"),
  pubcons     = list(label = "Public consumption",    mode = "level", level = "pubcons_cvm"),
  pubinv      = list(label = "Public investment",     mode = "level", level = "pubinv_cvm"),
  exports     = list(label = "Exports",               mode = "level", level = "exports_cvm"),
  imports     = list(label = "Imports",               mode = "level", level = "imports_cvm", negate = TRUE),
  inventories = list(label = "Inventories",           mode = "contrib", contrib = "inv_contrib"),
  discrepancy = list(label = "Statistical discrepancy", mode = "contrib", contrib = "disc_contrib")
)

# Display names for detected releases.
RELEASE_NAMES <- c(
  natacc = "National Accounts (GDP)", hours = "Labour Force Survey",
  lfs = "Labour Force Survey", mhsi = "Household Spending Indicator",
  trade = "International Trade in Goods", approvals = "Building Approvals",
  construction = "Construction Work Done", capex = "Private New Capex",
  busind = "Business Indicators", bop = "Balance of Payments",
  cpi = "Monthly CPI", cpi_old = "Monthly CPI Indicator (hist.)",
  vacancies = "Job Vacancies",
  gfs = "Government Finance Statistics", rba_credit = "RBA Credit Aggregates",
  nab = "NAB Business Survey"
)

PATHS <- list(
  vintages = "data/vintages",
  history  = "data/nowcast_history.csv",
  impacts  = "data/release_impacts.csv",
  errors   = "data/final_errors.csv",
  heartbeat = "data/heartbeat.csv",
  nab      = "data/manual/nab",
  site     = "site",
  backtest = "data/backtest_summary.csv",
  weights  = "data/blend_weights.csv"
)
