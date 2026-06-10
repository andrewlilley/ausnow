# Release attribution: impact of each detected release on the blended nowcast.
#
# Sequential method (GDPNow-style): start from the previous vintage, swap in
# each changed source one at a time in publication order, recompute the full
# nowcast after each swap. Impacts sum exactly to the total change between the
# two vintages by construction.

#' @param new,prev vintage objects (list(data=...)); prev may be NULL.
#' @param releases data.frame from detect_releases() (key, kind, ...).
#' @param target_q target quarter label.
#' @param asof run date.
#' @return list(rows = impact rows, final = final nowcast object)
attribute_releases <- function(new, prev, releases, target_q, asof) {
  if (is.null(prev) || is.null(releases) || nrow(releases) == 0) {
    nc <- nowcast_quarter(new$data, target_q, asof)
    return(list(rows = NULL, final = nc))
  }
  # publication order: sources whose pub-day-of-cycle is earlier first; within
  # a single run day we order by each source's typical lag (a proxy for the
  # actual intraday order, which the ABS does not publish)
  ord <- order(vapply(releases$key, function(k) INDICATORS[[k]]$pub_lag_days %||% 35, 0))
  releases <- releases[ord, , drop = FALSE]

  cur <- prev$data
  # carry sources that exist only in the new vintage but didn't change
  for (k in setdiff(names(new$data), names(cur))) {
    if (!k %in% releases$key) cur[[k]] <- new$data[[k]]
  }
  base <- nowcast_quarter(cur, target_q, asof)
  rows <- list()
  prev_est <- if (is.null(base)) NA_real_ else base$blend
  for (i in seq_len(nrow(releases))) {
    k <- releases$key[i]
    cur[[k]] <- new$data[[k]]
    nc <- nowcast_quarter(cur, target_q, asof)
    est <- if (is.null(nc)) NA_real_ else nc$blend
    rows[[i]] <- data.frame(
      run_date = format(asof),
      publication_date = format(asof),
      release = RELEASE_NAMES[[k]] %||% k,
      source_key = k,
      kind = releases$kind[i],
      target_quarter = target_q,
      old_estimate = round(prev_est, 4),
      new_estimate = round(est, 4),
      impact_pp = round(est - prev_est, 4),
      component = INDICATORS[[k]]$component %||% ""
    )
    prev_est <- est
  }
  final <- nowcast_quarter(new$data, target_q, asof)
  rows <- dplyr::bind_rows(rows)
  # numerical safety: any residual between the last sequential step and the
  # full recompute (should be ~0) is folded into the last row
  resid <- final$blend - prev_est
  if (is.finite(resid) && abs(resid) > 1e-9 && nrow(rows) > 0) {
    rows$new_estimate[nrow(rows)] <- round(final$blend, 4)
    rows$impact_pp[nrow(rows)] <- round(rows$new_estimate[nrow(rows)] -
                                        rows$old_estimate[nrow(rows)], 4)
  }
  list(rows = rows, final = final, baseline = base)
}
