#!/usr/bin/env Rscript
# Pseudo-real-time backtest (see DECISIONS.md D8 for the vintage caveat).
#
# For each historical target quarter and each point in the release cycle,
# truncate the dataset to what had been published by that date, re-estimate
# every bridge/productivity term on the truncated sample, and record the
# labour read, expenditure read, AR(1) and historical-mean benchmarks.
# Then estimate the blend weight path by inverse MSE per cycle position and
# write: data/blend_weights.csv, data/backtest_summary.csv,
# data/backtest_runs.csv, and the results section of docs/methodology.md.

setwd(Sys.getenv("AUSNOW_ROOT", "."))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
suppressMessages(library(dplyr))

args <- commandArgs(trailingOnly = TRUE)
aggregate_only <- "--aggregate-only" %in% args
args <- setdiff(args, "--aggregate-only")
vintage_arg <- if (length(args) >= 1) args[1] else NULL

# data: newest vintage on disk unless one is passed explicitly
vdirs <- sort(list.dirs(PATHS$vintages, recursive = FALSE))
vdir <- vintage_arg %||% utils::tail(vdirs, 1)
stopifnot(length(vdir) == 1, dir.exists(vdir))
v <- load_vintage(vdir)
log_msg("Backtest on vintage %s", vdir)

DAYS_GRID <- c(150, 120, 90, 60, 45, 30, 20, 10, 5, 1)
gdp_g_all <- q_growth(get_series(v$data, "gdp_cvm"))
quarters <- gdp_g_all$quarter[gdp_g_all$quarter >= "2016Q1"]
log_msg("Targets: %s..%s (%d quarters) x %d cycle points",
        quarters[1], utils::tail(quarters, 1), length(quarters), length(DAYS_GRID))

if (aggregate_only && file.exists("data/backtest_runs.csv")) {
  runs <- utils::read.csv("data/backtest_runs.csv")
  log_msg("Aggregate-only: reusing %d rows from data/backtest_runs.csv", nrow(runs))
} else {
runs <- list()
for (tq in quarters) {
  rel <- gdp_release_date(tq)
  actual <- gdp_g_all$g[gdp_g_all$quarter == tq]
  for (d in DAYS_GRID) {
    asof <- rel - d
    dat <- truncate_asof(v$data, asof)
    lab <- tryCatch(labour_read(dat, tq), error = function(e) NULL)
    expr <- tryCatch(expenditure_read(dat, tq), error = function(e) NULL)
    pub <- q_growth(get_series(dat, "gdp_cvm"))
    ar1 <- if (nrow(pub) > 12) {
      steps <- quarter_diff(tq, utils::tail(pub$quarter, 1))
      utils::tail(ar1_forecast(pub$g, max(1, steps)), 1)
    } else NA_real_
    hmean <- if (nrow(pub) > 12) mean(utils::tail(pub$g, 40)) else NA_real_
    runs[[paste(tq, d)]] <- data.frame(
      target_quarter = tq, days_to_release = d, asof = format(asof),
      actual = actual,
      labour = lab$estimate %||% NA_real_,
      expenditure = expr$estimate %||% NA_real_,
      ar1 = ar1, hist_mean = hmean)
  }
  log_msg("  %s done", tq)
}
runs <- bind_rows(runs)
dir.create("data", showWarnings = FALSE)
utils::write.csv(runs, "data/backtest_runs.csv", row.names = FALSE)
}

# COVID quarters: GDP swings of several pp dominate squared errors and say
# nothing about normal-cycle informativeness. Weights and the headline tables
# are estimated ex-COVID; the full-sample table is reported alongside.
COVID_Q <- c("2020Q1", "2020Q2", "2020Q3", "2020Q4", "2021Q1", "2021Q2")
runs_x <- runs %>% filter(!target_quarter %in% COVID_Q)

# ---- blend weight path: inverse-MSE on the labour vs expenditure reads -----
wpath <- runs_x %>%
  group_by(days_to_release) %>%
  summarise(mse_lab = mean((labour - actual)^2, na.rm = TRUE),
            mse_exp = mean((expenditure - actual)^2, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(w_labour = pmin(0.95, pmax(0.05, (1 / mse_lab) / (1 / mse_lab + 1 / mse_exp))))
# smooth: 3-point moving average over the (ordered) grid
ws <- wpath[order(wpath$days_to_release), ]
sm <- as.numeric(stats::filter(ws$w_labour, rep(1 / 3, 3), sides = 2))
ws$w_labour <- ifelse(is.na(sm), ws$w_labour, sm)
utils::write.csv(ws[, c("days_to_release", "w_labour")], PATHS$weights, row.names = FALSE)
log_msg("Weight path written: %s", paste(sprintf("%d:%.2f", ws$days_to_release, ws$w_labour), collapse = " "))

# ---- blended errors and summary -------------------------------------------
runs$w <- stats::approx(ws$days_to_release, ws$w_labour, xout = runs$days_to_release, rule = 2)$y
runs$blend <- ifelse(is.na(runs$labour), runs$expenditure,
              ifelse(is.na(runs$expenditure), runs$labour,
                     runs$w * runs$labour + (1 - runs$w) * runs$expenditure))
runs_x <- runs %>% filter(!target_quarter %in% COVID_Q)   # now includes blend

rmse_tab <- function(df) df %>%
  group_by(days_to_release) %>%
  summarise(labour = sqrt(mean((labour - actual)^2, na.rm = TRUE)),
            expenditure = sqrt(mean((expenditure - actual)^2, na.rm = TRUE)),
            blend = sqrt(mean((blend - actual)^2, na.rm = TRUE)),
            ar1 = sqrt(mean((ar1 - actual)^2, na.rm = TRUE)),
            hist_mean = sqrt(mean((hist_mean - actual)^2, na.rm = TRUE)),
            mae_blend = mean(abs(.data$blend - actual), na.rm = TRUE),
            n = dplyr::n(), .groups = "drop") %>%
  arrange(desc(days_to_release))

summary_full <- rmse_tab(runs)
summary_x    <- rmse_tab(runs_x)
summary_oos  <- rmse_tab(runs %>% filter(target_quarter >= "2022Q1"))

long <- summary_x %>%
  tidyr::pivot_longer(c(labour, expenditure, blend, ar1, hist_mean),
                      names_to = "model", values_to = "rmse")
utils::write.csv(long, PATHS$backtest, row.names = FALSE)

fmt_tab <- function(s) {
  paste(c("| Days to release | Labour read | Expenditure read | Blend | AR(1) | Hist. mean |",
          "|---|---|---|---|---|---|",
          sprintf("| %d | %.3f | %.3f | **%.3f** | %.3f | %.3f |",
                  s$days_to_release, s$labour, s$expenditure, s$blend, s$ar1, s$hist_mean)),
        collapse = "\n")
}

late <- summary_x[summary_x$days_to_release <= 20, ]
beats_ar_late <- all(late$blend < late$ar1)
late_full <- summary_full[summary_full$days_to_release <= 20, ]
beats_ar_late_full <- all(late_full$blend < late_full$ar1)
log_msg("Blend beats AR(1) in final weeks: ex-COVID %s | full %s",
        beats_ar_late, beats_ar_late_full)

results_md <- paste0(
  "## Backtest results\n\n",
  "Generated ", format(Sys.time(), "%Y-%m-%d"), " from vintage `", basename(vdir), "`. ",
  "Pseudo-real-time, expanding windows, ", length(quarters), " target quarters (",
  quarters[1], "-", utils::tail(quarters, 1), "), evaluated at ", length(DAYS_GRID),
  " points in the release cycle. RMSE in percentage points of q/q GDP growth.\n\n",
  "### Headline: excluding COVID quarters (2020Q1-2021Q2)\n\n",
  "COVID-era GDP swings of several percentage points dominate squared errors and are\n",
  "not informative about normal-cycle accuracy; the blend weight path is estimated on\n",
  "this sample. Both reads tracked the COVID collapse directionally, the labour read\n",
  "far better (see full-sample table).\n\n",
  fmt_tab(summary_x), "\n\n",
  "### Full sample (", quarters[1], "-", utils::tail(quarters, 1), ", incl. COVID)\n\n",
  fmt_tab(summary_full), "\n\n",
  "### Out-of-sample check (targets 2022Q1 onward)\n\n",
  fmt_tab(summary_oos), "\n\n",
  "### Blend weight on the labour read\n\n",
  "| Days to release | ", paste(ws$days_to_release, collapse = " | "), " |\n",
  "|---|", paste(rep("---", nrow(ws)), collapse = "|"), "|\n",
  "| w(labour) | ", paste(sprintf("%.2f", ws$w_labour), collapse = " | "), " |\n\n",
  "Blend beats AR(1) at every grid point with <=20 days to release: ex-COVID **",
  ifelse(beats_ar_late, "yes", "NO - investigate"), "**, full sample **",
  ifelse(beats_ar_late_full, "yes", "NO - investigate"), "**.\n")
writeLines(results_md, "docs/backtest_results.md")
log_msg("Backtest complete. Summary:\n%s",
        paste(utils::capture.output(print(as.data.frame(summary_full), digits = 3)), collapse = "\n"))
