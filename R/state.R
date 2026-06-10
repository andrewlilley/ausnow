# Quarter state machine and state-file persistence (idempotent appends).
#
# Live targets at any date: every quarter after the latest published GDP
# quarter, up to and including the quarter containing `today`. Normally one or
# two: the completed-but-unreleased quarter and the current quarter. In the
# window right after a GDP release (before the next quarter ends) there is one.

#' @param last_published quarter label of the latest published GDP quarter.
#' @param today Date.
live_targets <- function(last_published, today) {
  current <- quarter_label(today)
  if (last_published >= current) return(character(0))
  q <- shift_quarter(last_published, 1)
  out <- character(0)
  while (q <= current) { out <- c(out, q); q <- shift_quarter(q, 1) }
  out
}

target_status <- function(qlab, today) {
  if (today > quarter_end(qlab)) "completed-unreleased" else "current"
}

#' Append-or-replace rows keyed by key_cols (idempotent re-runs).
upsert_csv <- function(path, rows, key_cols) {
  if (is.null(rows) || nrow(rows) == 0) return(invisible(NULL))
  if (file.exists(path)) {
    old <- utils::read.csv(path, colClasses = "character")
    rows_chr <- as.data.frame(lapply(rows, as.character))
    key_old <- do.call(paste, c(old[key_cols], sep = "\r"))
    key_new <- do.call(paste, c(rows_chr[key_cols], sep = "\r"))
    merged <- rbind(old[!key_old %in% key_new, , drop = FALSE], rows_chr)
    utils::write.csv(merged, path, row.names = FALSE)
  } else {
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    utils::write.csv(rows, path, row.names = FALSE)
  }
  invisible(NULL)
}

#' Record the nowcast history row for one run x target.
history_row <- function(nc, run_date) {
  comp <- nc$exp_detail$components
  getc <- function(cn) {
    v <- comp$contribution[comp$component == cn]
    if (length(v) == 1) round(v, 4) else NA_real_
  }
  data.frame(
    run_date = format(run_date),
    target_quarter = nc$target_quarter,
    status = target_status(nc$target_quarter, run_date),
    model_only = nc$model_only,
    blend = round(nc$blend, 4),
    labour_read = round(nc$labour, 4),
    expenditure_read = round(nc$expenditure, 4),
    w_labour = round(nc$w_labour, 4),
    days_to_release = nc$days_to_release,
    band = round(nc$band, 4),
    months_hours_observed = nc$months_observed,
    c_hfce = getc("hfce"), c_dwell = getc("dwell"), c_otc = getc("otc"),
    c_businv = getc("businv"), c_pubcons = getc("pubcons"),
    c_pubinv = getc("pubinv"), c_exports = getc("exports"),
    c_imports = getc("imports"), c_inventories = getc("inventories"),
    c_discrepancy = getc("discrepancy"),
    bias_correction = round(nc$exp_detail$bias %||% NA_real_, 4)
  )
}

#' When a new GDP print covers quarter Q: record the final nowcast error for Q
#' from the last history row before the release, then Q is naturally retired
#' (it stops being a live target).
record_final_errors <- function(data, run_date) {
  gdp_g <- q_growth(get_series(data, "gdp_cvm"))
  if (!file.exists(PATHS$history) || nrow(gdp_g) == 0) return(invisible(NULL))
  hist <- utils::read.csv(PATHS$history)
  done <- if (file.exists(PATHS$errors)) utils::read.csv(PATHS$errors)$target_quarter else character(0)
  rows <- list()
  for (q in unique(hist$target_quarter)) {
    actual <- gdp_g$g[gdp_g$quarter == q]
    if (length(actual) != 1 || q %in% done) next
    h <- hist[hist$target_quarter == q, ]
    h <- h[order(h$run_date), ]
    last <- utils::tail(h, 1)
    rows[[q]] <- data.frame(
      target_quarter = q,
      outcome_first_print = round(actual, 4),
      final_blend = last$blend, final_labour = last$labour_read,
      final_expenditure = last$expenditure_read,
      err_blend = round(last$blend - actual, 4),
      err_labour = round(last$labour_read - actual, 4),
      err_expenditure = round(last$expenditure_read - actual, 4),
      last_run_before_release = last$run_date,
      recorded_on = format(run_date)
    )
  }
  if (length(rows) > 0)
    upsert_csv(PATHS$errors, dplyr::bind_rows(rows), "target_quarter")
  invisible(NULL)
}

heartbeat <- function(run_date, status, note = "") {
  upsert_csv(PATHS$heartbeat,
             data.frame(run_date = format(run_date), status = status,
                        note = substr(note, 1, 400)),
             key_cols = "run_date")
}
