# Static site generator: collects state CSVs into one JSON payload and bakes
# it into site/index.html from site/template.html. No build framework.

suppressMessages(library(dplyr))

build_site <- function(run_date, vintage) {
  payload <- tryCatch(site_payload(run_date, vintage), error = function(e) {
    log_msg("WARN site: payload build failed (%s)", conditionMessage(e))
    NULL
  })
  if (is.null(payload)) return(invisible(FALSE))
  tpl_path <- file.path(PATHS$site, "template.html")
  if (!file.exists(tpl_path)) { log_msg("WARN site: template missing"); return(invisible(FALSE)) }
  tpl <- paste(readLines(tpl_path, warn = FALSE), collapse = "\n")
  json <- jsonlite::toJSON(payload, auto_unbox = TRUE, na = "null", digits = 4)
  parts <- strsplit(tpl, "/*__AUSNOW_DATA__*/null", fixed = TRUE)[[1]]
  if (length(parts) != 2) { log_msg("WARN site: data token not found in template"); return(invisible(FALSE)) }
  out <- paste0(parts[1], json, parts[2])
  out <- gsub("__REPO__", repo_slug(), out, fixed = TRUE)
  writeLines(out, file.path(PATHS$site, "index.html"))
  log_msg("Site rebuilt: site/index.html (%.0f kB)", nchar(out) / 1024)
  invisible(TRUE)
}

site_payload <- function(run_date, vintage) {
  hist <- if (file.exists(PATHS$history)) utils::read.csv(PATHS$history) else NULL
  imps <- if (file.exists(PATHS$impacts)) utils::read.csv(PATHS$impacts) else NULL
  errs <- if (file.exists(PATHS$errors)) utils::read.csv(PATHS$errors) else NULL
  bt   <- if (file.exists(PATHS$backtest)) utils::read.csv(PATHS$backtest) else NULL
  wts  <- if (file.exists(PATHS$weights)) utils::read.csv(PATHS$weights) else NULL

  gdp_g <- q_growth(get_series(vintage$data, "gdp_cvm"))
  last_pub <- utils::tail(gdp_g$quarter, 1)
  targets_now <- live_targets(last_pub, run_date)

  # headline cards: latest history row per live target + change vs previous run
  cards <- list()
  for (tq in targets_now) {
    h <- hist[hist$target_quarter == tq, ]
    if (is.null(h) || nrow(h) == 0) next
    h <- h[order(h$run_date), ]
    last <- utils::tail(h, 1); prev <- if (nrow(h) > 1) h[nrow(h) - 1, ] else NULL
    cards[[tq]] <- list(
      quarter = tq, quarter_pretty = pretty_quarter(tq),
      status = target_status(tq, run_date),
      model_only = isTRUE(as.logical(last$model_only)),
      blend = last$blend, labour = last$labour_read, expenditure = last$expenditure_read,
      w_labour = last$w_labour, band = last$band,
      change = if (!is.null(prev)) round(last$blend - prev$blend, 3) else NA_real_,
      days_to_release = last$days_to_release,
      release_date = format(gdp_release_date(tq)),
      months_hours = last$months_hours_observed,
      run_date = last$run_date
    )
  }

  # evolution series per quarter (live + archived)
  evol <- list()
  if (!is.null(hist)) {
    for (tq in unique(hist$target_quarter)) {
      h <- hist[hist$target_quarter == tq, ]
      h <- h[order(h$run_date), ]
      outcome <- if (!is.null(errs) && tq %in% errs$target_quarter)
        errs$outcome_first_print[errs$target_quarter == tq][1] else NULL
      evol[[tq]] <- list(
        quarter = tq, quarter_pretty = pretty_quarter(tq),
        dates = I(h$run_date), blend = I(h$blend),
        labour = I(h$labour_read), expenditure = I(h$expenditure_read),
        band = I(h$band), outcome = outcome,
        release_date = format(gdp_release_date(tq)))
    }
  }

  # release impact table, newest first
  impacts <- NULL
  if (!is.null(imps) && nrow(imps) > 0) {
    imps <- imps[order(imps$run_date, decreasing = TRUE), ]
    impacts <- utils::head(imps, 200)
  }

  # component contributions for the lead target
  contrib <- NULL
  if (length(cards) > 0 && !is.null(hist)) {
    tq <- names(cards)[1]
    h <- hist[hist$target_quarter == tq, ]
    last <- utils::tail(h[order(h$run_date), ], 1)
    cols <- c(c_hfce = "Consumption", c_dwell = "Dwellings", c_otc = "Transfer costs",
              c_businv = "Business inv.", c_pubcons = "Public cons.",
              c_pubinv = "Public inv.", c_exports = "Exports", c_imports = "Imports",
              c_inventories = "Inventories", c_discrepancy = "Discrepancy")
    contrib <- list(quarter = pretty_quarter(tq),
                    labels = I(unname(cols)),
                    values = I(unname(vapply(names(cols), function(cn)
                      as.numeric(last[[cn]]) %||% NA_real_, 0))))
  }

  # upcoming releases + NAB status
  up <- tryCatch(upcoming_releases(run_date, 5), error = function(e) NULL)
  upcoming <- if (!is.null(up) && nrow(up) > 0) {
    lapply(seq_len(nrow(up)), function(i) list(
      title = clean_title(up$title[i]), date = format(up$date[i]),
      estimated = isTRUE(up$estimated[i])))
  } else list()
  nabst <- nab_status(vintage$data$nab, run_date)

  # stale sources
  stale <- if (!is.null(vintage$status)) {
    s <- vintage$status[!vintage$status$ok, ]
    if (nrow(s) > 0) lapply(seq_len(nrow(s)), function(i) list(
      key = s$key[i], label = INDICATORS[[s$key[i]]]$label %||% s$key[i],
      latest = format(s$latest[i]))) else list()
  } else list()

  # backtest curves for the methodology section
  backtest <- if (!is.null(bt)) {
    list(days = I(sort(unique(bt$days_to_release), decreasing = TRUE)),
         series = lapply(split(bt, bt$model), function(s) {
           s <- s[order(-s$days_to_release), ]
           list(model = s$model[1], rmse = I(s$rmse))
         }) |> unname())
  } else NULL
  weights <- if (!is.null(wts)) list(days = I(wts$days_to_release), w = I(wts$w_labour)) else NULL

  archived <- if (!is.null(errs) && nrow(errs) > 0) {
    e <- errs[order(errs$target_quarter, decreasing = TRUE), ]
    lapply(seq_len(nrow(e)), function(i) list(
      quarter = e$target_quarter[i], quarter_pretty = pretty_quarter(e$target_quarter[i]),
      outcome = e$outcome_first_print[i], final_blend = e$final_blend[i],
      err_blend = e$err_blend[i], err_labour = e$err_labour[i],
      err_expenditure = e$err_expenditure[i]))
  } else list()

  list(
    generated = format(as.POSIXct(Sys.time(), tz = SYD_TZ), "%Y-%m-%d %H:%M %Z"),
    run_date = format(run_date),
    last_published = list(quarter = last_pub, quarter_pretty = pretty_quarter(last_pub),
                          growth = round(utils::tail(gdp_g$g, 1), 2)),
    cards = unname(cards),
    evolution = unname(evol),
    impacts = impacts,
    contributions = contrib,
    upcoming = upcoming,
    nab = nabst[c("available", "message")],
    stale = stale,
    backtest = backtest,
    weights = weights,
    archived = archived
  )
}

#' "owner/repo" from the git remote (or a GitHub Actions env var), for links.
repo_slug <- function() {
  slug <- Sys.getenv("GITHUB_REPOSITORY", "")
  if (nzchar(slug)) return(slug)
  url <- tryCatch(system2("git", c("config", "--get", "remote.origin.url"),
                          stdout = TRUE, stderr = FALSE), error = function(e) "")
  m <- regmatches(url, regexpr("github\\.com[:/]([^/]+/[^/.]+)", url))
  if (length(m) == 1) sub("github\\.com[:/]", "", m) else "ausnow"
}

pretty_quarter <- function(q) {
  paste0(c("1" = "Q1", "2" = "Q2", "3" = "Q3", "4" = "Q4")[substr(q, 6, 6)], " ", substr(q, 1, 4))
}

clean_title <- function(t) {
  t <- sub(",? Australia.*$", "", t)
  sub("Australian National Accounts.*", "National Accounts (GDP)", t)
}
