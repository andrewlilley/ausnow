# Fetch layer: every source trapped individually; on failure we degrade to the
# previous vintage for that source and flag it stale. A vintage is a named list
# of data.frames (series_id, series, date, value) plus a fetch status table.

suppressMessages({
  library(dplyr)
})

#' Fetch one source. Returns data.frame(series_id, series, date, value) or NULL.
fetch_source <- function(key, spec) {
  f <- spec$fetch
  if (f$type == "abs_ts") {
    df <- readabs::read_abs(f$cat_no, tables = f$tables,
                            check_local = FALSE, show_progress_bars = FALSE)
    df <- df %>%
      filter(series_type %in% c("Seasonally Adjusted", "Original")) %>%
      group_by(series_id) %>%
      # prefer seasonally adjusted where both exist for one id (never happens
      # in practice; ids are unique per type) — keep all, dedupe on date
      ungroup() %>%
      select(series_id, series, date, value, series_type)
    # If both SA and Original exist for the same series text, SA ids differ, so
    # no further filtering needed; drop type to standardize.
    df %>% select(series_id, series, date, value) %>% distinct()
  } else if (f$type == "abs_series") {
    readabs::read_abs_series(f$series_ids, show_progress_bars = FALSE) %>%
      select(series_id, series, date, value) %>% distinct()
  } else if (f$type == "abs_cube") {
    fetch_gfs(f$cat_string)
  } else if (f$type == "rba_table") {
    readrba::read_rba(table_no = f$table_no) %>%
      transmute(series_id, series, date = as.Date(date), value) %>% distinct()
  } else if (f$type == "nab_folder") {
    read_nab_folder(f$path)
  } else stop("unknown fetch type: ", f$type)
}

#' GFS cube: download the quarterly xlsx, locate the national public sector
#' aggregates by header matching, return synthetic series GFS_PUBDEM (general
#' government final consumption + public GFCF, current prices, $m).
fetch_gfs <- function(cat_string) {
  files <- readabs::get_available_files(cat_string)
  cand <- files[grepl("quarter", files$label, ignore.case = TRUE) |
                grepl("Quarter", files$file), , drop = FALSE]
  if (nrow(cand) == 0) cand <- files
  tmp <- file.path(tempdir(), "gfs_cube")
  dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
  path <- readabs::download_abs_data_cube(cat_string, cand$file[1], path = tmp)
  parse_gfs_cube(path)
}

#' Defensive GFS parser: scan sheets for a quarterly time-series layout with
#' rows/cols matching "final consumption expenditure" and "gross fixed capital
#' formation". ABS GFS Table 1 ("Key aggregates") has quarters in columns.
parse_gfs_cube <- function(path) {
  sheets <- readxl::excel_sheets(path)
  data_sheets <- sheets[grepl("Table|Data", sheets, ignore.case = TRUE)]
  if (length(data_sheets) == 0) data_sheets <- sheets
  for (sh in data_sheets) {
    raw <- tryCatch(
      suppressMessages(readxl::read_excel(path, sheet = sh, col_names = FALSE,
                                          .name_repair = "minimal")),
      error = function(e) NULL)
    if (is.null(raw) || nrow(raw) < 5) next
    m <- as.matrix(raw)
    # find a row whose cells parse as quarter labels (e.g. "Mar Qtr 2026",
    # "Mar-2026", or Excel dates)
    date_row <- NA
    for (i in seq_len(min(nrow(m), 15))) {
      parsed <- parse_gfs_dates(m[i, ])
      if (sum(!is.na(parsed)) >= 8) { date_row <- i; dates <- parsed; break }
    }
    if (is.na(date_row)) next
    lab <- apply(m, 1, function(r) paste(stats::na.omit(r[1:2]), collapse = " "))
    fce_row  <- which(grepl("final consumption expenditure", lab, ignore.case = TRUE) &
                      !grepl("\\bstate\\b|local", lab, ignore.case = TRUE))[1]
    gfcf_row <- which(grepl("gross fixed capital formation", lab, ignore.case = TRUE) &
                      !grepl("\\bstate\\b|local", lab, ignore.case = TRUE))[1]
    if (is.na(fce_row) || is.na(gfcf_row)) next
    num <- function(i) suppressWarnings(as.numeric(m[i, ]))
    ok <- !is.na(dates)
    v <- num(fce_row)[ok] + num(gfcf_row)[ok]
    d <- dates[ok]
    keep <- !is.na(v)
    if (sum(keep) < 8) next
    return(data.frame(series_id = "GFS_PUBDEM",
                      series = "GFS national public demand (FCE + GFCF, current prices)",
                      date = d[keep], value = v[keep]))
  }
  stop("GFS cube format not recognised: ", basename(path))
}

parse_gfs_dates <- function(cells) {
  out <- as.Date(rep(NA, length(cells)))
  for (j in seq_along(cells)) {
    x <- cells[j]
    if (is.na(x) || !nzchar(x)) next
    xn <- suppressWarnings(as.numeric(x))
    if (!is.na(xn) && xn > 20000 && xn < 80000) {           # Excel serial date
      out[j] <- as.Date(xn, origin = "1899-12-30"); next
    }
    mm <- regmatches(x, regexpr("(Mar|Jun|Sep|Dec)[a-z]*[ .-]+(Qtr|Quarter)?[ .-]*([0-9]{4})", x, ignore.case = TRUE))
    if (length(mm) == 1) {
      mon <- c(Mar = 1, Jun = 4, Sep = 7, Dec = 10)[substr(mm, 1, 3)]
      yr <- as.integer(regmatches(mm, regexpr("[0-9]{4}", mm)))
      if (!is.na(mon) && !is.na(yr)) out[j] <- as.Date(sprintf("%d-%02d-01", yr, mon))
    }
  }
  out
}

#' Fetch everything. Returns list(data = named list of df, status = df).
#' On per-source failure, substitutes the previous vintage's data (stale).
fetch_all <- function(prev = NULL, keys = names(INDICATORS)) {
  data <- list(); status <- list()
  for (key in keys) {
    spec <- INDICATORS[[key]]
    res <- tryCatch(fetch_source(key, spec), error = function(e) e)
    if (key == "nab" && !inherits(res, "error") && (is.null(res) || nrow(res) == 0)) {
      # empty drop folder is a normal state, not a failure
      status[[key]] <- data.frame(key = key, ok = TRUE, stale = FALSE,
                                  note = "drop folder empty; model runs without NAB",
                                  latest = as.Date(NA))
      log_msg("ok   nab: drop folder empty (model runs without NAB)")
      next
    }
    if (inherits(res, "error") || is.null(res) || nrow(res) == 0) {
      msg <- if (inherits(res, "error")) conditionMessage(res) else "no data"
      old <- prev$data[[key]]
      if (!is.null(old)) {
        data[[key]] <- old
        status[[key]] <- data.frame(key = key, ok = FALSE, stale = TRUE,
                                    note = paste("fetch failed, using previous vintage:",
                                                 substr(msg, 1, 150)),
                                    latest = max(old$date))
        log_msg("WARN %s: fetch failed (%s) — degraded to previous vintage", key, substr(msg, 1, 80))
      } else {
        status[[key]] <- data.frame(key = key, ok = FALSE, stale = TRUE,
                                    note = paste("fetch failed, no previous vintage:",
                                                 substr(msg, 1, 150)),
                                    latest = as.Date(NA))
        log_msg("WARN %s: fetch failed and no previous vintage (%s)", key, substr(msg, 1, 80))
      }
    } else {
      res$date <- as.Date(res$date)
      data[[key]] <- as.data.frame(res)
      status[[key]] <- data.frame(key = key, ok = TRUE, stale = FALSE, note = "",
                                  latest = max(res$date))
      log_msg("ok   %s: %d rows, latest %s", key, nrow(res), format(max(res$date)))
    }
  }
  list(data = data, status = bind_rows(status))
}

# ---- vintages -------------------------------------------------------------

vintage_dir <- function(run_date) file.path(PATHS$vintages, format(run_date))

save_vintage <- function(vintage, run_date) {
  dir <- vintage_dir(run_date)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  for (key in names(vintage$data)) {
    saveRDS(vintage$data[[key]], file.path(dir, paste0(key, ".rds")))
  }
  utils::write.csv(vintage$status, file.path(dir, "status.csv"), row.names = FALSE)
  manifest <- lapply(names(vintage$data), function(key) {
    df <- vintage$data[[key]]
    data.frame(key = key, n = nrow(df), latest = format(max(df$date)),
               hash = digest_df(df))
  })
  utils::write.csv(bind_rows(manifest), file.path(dir, "manifest.csv"), row.names = FALSE)
  invisible(dir)
}

#' Stable content hash of a series data.frame (order-independent).
digest_df <- function(df) {
  df <- df[order(df$series_id, df$date), c("series_id", "date", "value")]
  paste0(nrow(df), "-",
         format(sum(df$value %% 997, na.rm = TRUE), digits = 15), "-",
         format(max(df$date)))
}

load_vintage <- function(dir) {
  files <- list.files(dir, pattern = "\\.rds$", full.names = TRUE)
  data <- stats::setNames(lapply(files, readRDS),
                          sub("\\.rds$", "", basename(files)))
  status_path <- file.path(dir, "status.csv")
  status <- if (file.exists(status_path)) {
    s <- utils::read.csv(status_path)
    s$latest <- as.Date(s$latest)
    s
  } else NULL
  for (k in names(data)) data[[k]]$date <- as.Date(data[[k]]$date)
  list(data = data, status = status, dir = dir)
}

#' Latest vintage strictly before run_date (so same-day reruns diff against
#' yesterday's snapshot, keeping reruns idempotent).
load_prev_vintage <- function(run_date) {
  if (!dir.exists(PATHS$vintages)) return(NULL)
  dirs <- sort(list.dirs(PATHS$vintages, recursive = FALSE))
  dirs <- dirs[basename(dirs) < format(run_date)]
  if (length(dirs) == 0) return(NULL)
  load_vintage(dirs[length(dirs)])
}

#' Diff two vintages -> detected releases: one row per source whose content
#' changed (new observations or revisions).
detect_releases <- function(new, prev) {
  out <- list()
  for (key in names(new$data)) {
    ndf <- new$data[[key]]
    odf <- prev$data[[key]]
    if (is.null(odf)) {
      out[[key]] <- data.frame(key = key, kind = "new_source",
                               new_obs = nrow(ndf), latest = max(ndf$date))
      next
    }
    if (identical(digest_df(ndf), digest_df(odf))) next
    merged <- merge(ndf[, c("series_id", "date", "value")],
                    odf[, c("series_id", "date", "value")],
                    by = c("series_id", "date"), all.x = TRUE,
                    suffixes = c("_new", "_old"))
    fresh <- sum(is.na(merged$value_old))
    revised <- sum(!is.na(merged$value_old) &
                   abs(merged$value_new - merged$value_old) > 1e-9, na.rm = TRUE)
    if (fresh == 0 && revised == 0) next
    out[[key]] <- data.frame(
      key = key,
      kind = if (fresh > 0) "new_data" else "revision",
      new_obs = fresh, latest = max(ndf$date))
  }
  bind_rows(out)
}
