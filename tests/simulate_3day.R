#!/usr/bin/env Rscript
# Three consecutive simulated pipeline days in a scratch root, with no network:
#   day 1 (2026-06-10): seed vintage minus the latest hours + MHSI month
#   day 2 (2026-06-11): those observations "arrive" -> two attributed releases
#   day 3 (2026-06-12): a NAB survey file is dropped -> attributed release
#   day 3 again        : idempotency — re-running must not duplicate rows
#
# Usage: Rscript tests/simulate_3day.R  (run from the repo root; needs one real
# vintage under data/vintages/ to serve as the frozen data source)

repo <- normalizePath(".")
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

vdirs <- sort(list.dirs(file.path(repo, "data/vintages"), recursive = FALSE))
stopifnot(length(vdirs) > 0)
FULL <- load_vintage(vdirs[length(vdirs)])
message("Simulation source vintage: ", vdirs[length(vdirs)])

sim <- file.path(tempdir(), paste0("ausnow-sim-", as.integer(Sys.time())))
dir.create(file.path(sim, "data/manual/nab"), recursive = TRUE)
dir.create(file.path(sim, "site"), recursive = TRUE)
file.copy(file.path(repo, "site/template.html"), file.path(sim, "site/"))
if (file.exists(file.path(repo, "data/blend_weights.csv")))
  file.copy(file.path(repo, "data/blend_weights.csv"), file.path(sim, "data/"))
if (file.exists(file.path(repo, "data/backtest_summary.csv")))
  file.copy(file.path(repo, "data/backtest_summary.csv"), file.path(sim, "data/"))
setwd(sim)
message("Simulation root: ", sim)

drop_last_month <- function(df) {
  df[df$date < max(df$date), , drop = FALSE]
}

# fetch_source mock: serve the frozen vintage, with day-dependent availability
SIM_DAY <- 1
fetch_source <- function(key, spec) {
  if (key == "nab") return(read_nab_folder(spec$path %||% "data/manual/nab"))
  df <- FULL$data[[key]]
  if (is.null(df)) stop("no data for ", key)
  if (SIM_DAY == 1 && key %in% c("hours", "mhsi")) df <- drop_last_month(df)
  df
}
# calendar scrape must not hit the network either
fetch_release_calendar <- function(...) NULL

day <- function(n, date) {
  SIM_DAY <<- n
  Sys.setenv(AUSNOW_TODAY = date)
  message("\n========== simulated day ", n, " (", date, ") ==========")
  run_pipeline()
}

day(1, "2026-06-10")
day(2, "2026-06-11")

# day 3: a NAB file lands in the drop folder
months <- seq(as.Date("2022-01-01"), as.Date("2026-05-01"), by = "month")
set.seed(7)
nabdf <- data.frame(
  Month = format(months, "%b %Y"),
  `Business confidence` = round(rnorm(length(months), 3, 5), 1),
  `Business conditions` = round(rnorm(length(months), 6, 5), 1),
  `Capacity utilisation` = round(82 + cumsum(rnorm(length(months), 0, .3)), 1),
  check.names = FALSE)
write.csv(nabdf, "data/manual/nab/nab-survey-2026-06.csv", row.names = FALSE)
day(3, "2026-06-12")
day(3.5, "2026-06-12")   # idempotent re-run, same date

# ---- verification ----------------------------------------------------------
fail <- function(...) { message("SIM FAIL: ", ...); quit(status = 1) }
hist <- read.csv("data/nowcast_history.csv")
imps <- read.csv("data/release_impacts.csv")
hb <- read.csv("data/heartbeat.csv")

if (!setequal(unique(hist$run_date), c("2026-06-10", "2026-06-11", "2026-06-12")))
  fail("history run dates wrong: ", paste(unique(hist$run_date), collapse = ","))
if (anyDuplicated(hist[, c("run_date", "target_quarter")]))
  fail("duplicate history rows after idempotent re-run")
d2 <- imps[imps$run_date == "2026-06-11", ]
if (!all(c("hours", "mhsi") %in% d2$source_key))
  fail("day-2 hours/mhsi releases not attributed: ", paste(d2$source_key, collapse = ","))
d3 <- imps[imps$run_date == "2026-06-12", ]
if (!"nab" %in% d3$source_key) fail("day-3 NAB drop not attributed")
if (anyDuplicated(imps[, c("run_date", "source_key", "target_quarter")]))
  fail("duplicate impact rows after idempotent re-run")

# attribution arithmetic: day-2 impacts must sum to the day-over-day change
h10 <- hist$blend[hist$run_date == "2026-06-10"]
h11 <- hist$blend[hist$run_date == "2026-06-11"]
gap <- abs(sum(d2$impact_pp) - (h11 - h10))
if (gap > 0.02) fail(sprintf("day-2 impacts (%.4f) don't match estimate change (%.4f)",
                             sum(d2$impact_pp), h11 - h10))
if (!file.exists("site/index.html")) fail("site not built")
if (!any(grepl("AusNow", readLines("site/index.html", n = 50)))) fail("site looks wrong")
if (nrow(hb) < 3) fail("heartbeat rows missing")

message("\nSIMULATION OK: ", nrow(hist), " history rows, ", nrow(imps),
        " impact rows, heartbeats: ", paste(hb$status, collapse = ","))
message("history:")
print(hist[, c("run_date", "target_quarter", "blend", "labour_read",
               "expenditure_read", "w_labour", "model_only")])
print(imps[, c("run_date", "release", "impact_pp", "new_estimate")])
