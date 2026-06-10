# NAB monthly business survey drop-folder parser.
#
# Contract (documented in README): a human drops whatever monthly file NAB
# distributes into data/manual/nab/. We make no assumptions about filename or
# sheet layout beyond: some sheet contains a date-like column (or row header)
# and columns whose headers mention the indices we want. The pipeline must
# never fail because of this folder.
#
# Format assumptions logged here:
#  - xlsx/xls/csv accepted; newest file by modification time wins, all files
#    are parsed and merged (later files override overlapping months).
#  - We look for headers matching (case-insensitive): "business conditions",
#    "business confidence", "capacity utili[sz]ation", "employment",
#    "trading". Header may be in any of the first 12 rows.
#  - Dates may be Excel serials, "Jan-2026", "2026-01", "January 2026" etc.

read_nab_folder <- function(path = PATHS$nab) {
  if (!dir.exists(path)) return(empty_nab())
  files <- list.files(path, pattern = "\\.(xlsx|xls|csv)$", full.names = TRUE,
                      ignore.case = TRUE)
  files <- files[!grepl("^~\\$", basename(files))]
  if (length(files) == 0) return(empty_nab())
  files <- files[order(file.mtime(files))]
  out <- list()
  for (f in files) {
    parsed <- tryCatch(parse_nab_file(f), error = function(e) {
      log_msg("WARN nab: could not parse %s (%s)", basename(f),
              substr(conditionMessage(e), 1, 100))
      NULL
    })
    if (!is.null(parsed) && nrow(parsed) > 0) out[[f]] <- parsed
  }
  if (length(out) == 0) return(empty_nab())
  df <- do.call(rbind, out)
  # later files override earlier ones on the same (series_id, date)
  df <- df[!duplicated(df[, c("series_id", "date")], fromLast = TRUE), ]
  rownames(df) <- NULL
  df[order(df$series_id, df$date), ]
}

empty_nab <- function() {
  data.frame(series_id = character(), series = character(),
             date = as.Date(character()), value = numeric())
}

NAB_TARGETS <- list(
  NAB_CONDITIONS = "business\\s*conditions",
  NAB_CONFIDENCE = "business\\s*confidence",
  NAB_CAPUTIL    = "capacity\\s*utili[sz]ation",
  NAB_EMPLOYMENT = "^employment|employment\\s*(index)?$",
  NAB_TRADING    = "trading"
)

parse_nab_file <- function(path) {
  if (grepl("\\.csv$", path, ignore.case = TRUE)) {
    sheets <- list(csv = utils::read.csv(path, header = FALSE,
                                         stringsAsFactors = FALSE,
                                         check.names = FALSE))
  } else {
    sh <- readxl::excel_sheets(path)
    sheets <- lapply(sh, function(s)
      as.data.frame(suppressMessages(
        readxl::read_excel(path, sheet = s, col_names = FALSE,
                           .name_repair = "minimal"))))
    names(sheets) <- sh
  }
  for (nm in names(sheets)) {
    res <- parse_nab_sheet(sheets[[nm]])
    if (!is.null(res) && nrow(res) > 0) return(res)
  }
  empty_nab()
}

parse_nab_sheet <- function(raw) {
  if (is.null(raw) || nrow(raw) < 4 || ncol(raw) < 2) return(NULL)
  m <- as.matrix(raw); m[] <- as.character(m)
  # locate header row: a row where >=1 target pattern matches some cell
  header_row <- NA
  for (i in seq_len(min(nrow(m), 12))) {
    hits <- sum(vapply(NAB_TARGETS, function(p)
      any(grepl(p, m[i, ], ignore.case = TRUE)), logical(1)))
    if (hits >= 1) { header_row <- i; break }
  }
  if (is.na(header_row)) return(NULL)
  header <- m[header_row, ]
  body <- m[(header_row + 1):nrow(m), , drop = FALSE]
  # find the date column: most parseable dates in body
  scores <- apply(body, 2, function(col) sum(!is.na(parse_nab_dates(col))))
  date_col <- which.max(scores)
  if (scores[date_col] < 3) return(NULL)
  dates <- parse_nab_dates(body[, date_col])
  out <- list()
  for (sid in names(NAB_TARGETS)) {
    col <- which(grepl(NAB_TARGETS[[sid]], header, ignore.case = TRUE))[1]
    if (is.na(col)) next
    vals <- suppressWarnings(as.numeric(body[, col]))
    keep <- !is.na(dates) & !is.na(vals)
    if (sum(keep) < 3) next
    out[[sid]] <- data.frame(series_id = sid,
                             series = paste("NAB survey:", tolower(gsub("NAB_", "", sid))),
                             date = dates[keep], value = vals[keep])
  }
  if (length(out) == 0) return(NULL)
  do.call(rbind, out)
}

parse_nab_dates <- function(x) {
  out <- as.Date(rep(NA, length(x)))
  for (j in seq_along(x)) {
    v <- x[j]
    if (is.na(v) || !nzchar(v)) next
    vn <- suppressWarnings(as.numeric(v))
    if (!is.na(vn) && vn > 20000 && vn < 80000) {
      out[j] <- as.Date(vn, origin = "1899-12-30"); next
    }
    v <- trimws(v)
    # candidate parses: ISO, day-first, "May 2026"/"May-2026"/"2026-05"
    cands <- list(
      suppressWarnings(as.Date(v, format = "%Y-%m-%d")),
      suppressWarnings(as.Date(v, format = "%d/%m/%Y")),
      if (grepl("^[A-Za-z]{3,9}[- ][0-9]{4}$", v)) {
        my <- paste("01", gsub("-", " ", v))
        d1 <- suppressWarnings(as.Date(my, format = "%d %b %Y"))
        if (is.na(d1)) suppressWarnings(as.Date(my, format = "%d %B %Y")) else d1
      },
      if (grepl("^[0-9]{4}-[0-9]{2}$", v))
        suppressWarnings(as.Date(paste0(v, "-01")))
    )
    for (d in cands) {
      if (!is.null(d) && !is.na(d) &&
          d > as.Date("1990-01-01") && d < as.Date("2050-01-01")) {
        out[j] <- d; break
      }
    }
  }
  # normalize to first of month
  ok <- !is.na(out)
  out[ok] <- as.Date(format(out[ok], "%Y-%m-01"))
  out
}

#' NAB folder status for the site and the model gate.
nab_status <- function(nab_df, today = ausnow_today(), stale_after = 45) {
  if (is.null(nab_df) || nrow(nab_df) == 0) {
    return(list(available = FALSE, latest = NA,
                message = "NAB survey: awaiting this month's file"))
  }
  latest <- max(nab_df$date)
  # observation month + typical intra-month publication delay
  age <- as.numeric(today - latest)
  if (age > stale_after) {
    list(available = FALSE, latest = latest,
         message = sprintf("NAB survey: awaiting this month's file (latest data %s)",
                           format(latest, "%b %Y")))
  } else {
    list(available = TRUE, latest = latest,
         message = sprintf("NAB survey: received for %s", format(latest, "%b %Y")))
  }
}
