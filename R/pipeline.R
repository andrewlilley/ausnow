# Pipeline orchestration: one function, called by scripts/run_nowcast.R and by
# the simulation harness. Never throws on data problems.

run_pipeline <- function() {
  run_date <- ausnow_today()
  log_msg("AusNow run for %s", format(run_date))

  prev <- load_prev_vintage(run_date)
  vintage <- fetch_all(prev)
  if (length(vintage$data) == 0 || is.null(vintage$data$natacc)) {
    heartbeat(run_date, "degraded", "no national accounts data available; aborting without state change")
    log_msg("FATAL-SOFT: no usable data this run")
    return(invisible(0))
  }

  gdp_g <- q_growth(get_series(vintage$data, "gdp_cvm"))
  last_pub <- utils::tail(gdp_g$quarter, 1)
  targets <- live_targets(last_pub, run_date)
  log_msg("Last published GDP: %s | live targets: %s", last_pub,
          paste(targets, collapse = ", "))

  releases <- if (!is.null(prev)) detect_releases(vintage, prev) else NULL
  fresh <- !is.null(releases) && nrow(releases) > 0
  hist_q <- if (file.exists(PATHS$history))
    unique(utils::read.csv(PATHS$history)$target_quarter) else character(0)
  covered <- length(targets) == 0 || all(targets %in% hist_q)
  forced <- nzchar(Sys.getenv("AUSNOW_FORCE", ""))
  if (forced) log_msg("AUSNOW_FORCE set: recomputing even without new data")
  if (!is.null(prev) && !fresh && covered && !forced) {
    heartbeat(run_date, "no-news", "no new data detected; state unchanged")
    log_msg("No new data. Heartbeat recorded; exiting cleanly.")
    build_site(run_date, vintage)   # refresh timestamp/upcoming strip only
    return(invisible(0))
  }

  record_final_errors(vintage$data, run_date)

  for (tq in targets) {
    att <- tryCatch(attribute_releases(vintage, prev, releases, tq, run_date),
                    error = function(e) { log_msg("WARN attribution %s: %s", tq,
                                                  conditionMessage(e)); NULL })
    nc <- att$final
    if (is.null(nc)) { log_msg("WARN: no nowcast computable for %s", tq); next }
    upsert_csv(PATHS$history, history_row(nc, run_date),
               key_cols = c("run_date", "target_quarter"))
    if (!is.null(att$rows) && nrow(att$rows) > 0) {
      keep <- att$rows[abs(att$rows$impact_pp) >= 0.0005 |
                       att$rows$source_key == "natacc", , drop = FALSE]
      upsert_csv(PATHS$impacts, keep,
                 key_cols = c("run_date", "source_key", "target_quarter"))
    }
    log_msg("%s: blend %.2f (labour %.2f / exp %.2f, w_lab %.2f)",
            tq, nc$blend, nc$labour, nc$expenditure, nc$w_labour)
  }

  save_vintage(vintage, run_date)
  n_stale <- sum(!vintage$status$ok)
  heartbeat(run_date,
            if (n_stale > 0) "degraded" else "ok",
            sprintf("releases: %s; stale: %s",
                    paste(releases$key %||% "initial", collapse = ","),
                    paste(vintage$status$key[!vintage$status$ok], collapse = ",") %||% "none"))
  build_site(run_date, vintage)
  log_msg("Run complete.")
  invisible(0)
}
