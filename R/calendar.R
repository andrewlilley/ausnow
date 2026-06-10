# ABS release calendar: scrape upcoming releases; degrade to rule-based
# estimates if the scrape fails.

CAL_WATCH <- c(
  "Australian National Accounts: National Income, Expenditure and Product",
  "Labour Force, Australia",
  "Monthly Household Spending Indicator",
  "International Trade in Goods",
  "Building Approvals, Australia",
  "Construction Work Done, Australia",
  "Private New Capital Expenditure and Expected Expenditure",
  "Business Indicators, Australia",
  "Balance of Payments and International Investment Position",
  "Consumer Price Index, Australia",
  "Job Vacancies, Australia",
  "Government Finance Statistics"
)

fetch_release_calendar <- function(pages = 0:6) {
  rows <- list()
  for (p in pages) {
    url <- paste0("https://www.abs.gov.au/release-calendar/future-releases?page=", p)
    html <- tryCatch({
      con <- url(url, headers = c(`User-Agent` = "Mozilla/5.0 (AusNow nowcast bot)"))
      txt <- paste(readLines(con, warn = FALSE), collapse = "\n")
      close(con)
      txt
    }, error = function(e) NULL)
    if (is.null(html)) break
    chunks <- strsplit(html, "views-row")[[1]][-1]
    for (ch in chunks) {
      title <- regmatches(ch, regexpr('<h3[^>]*event-name[^>]*>[^<]+</h3>', ch))
      if (length(title) == 0)
        title <- regmatches(ch, regexpr('<h3[^>]*>[^<]+</h3>', ch))
      if (length(title) == 0) next
      title <- gsub("<[^>]+>", "", title)
      dt <- regmatches(ch, regexpr('datetime="[^"]+"', ch))
      if (length(dt) == 0) next
      dt <- sub('datetime="', "", sub('"$', "", dt))
      when <- as.POSIXct(dt, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
      rows[[length(rows) + 1]] <- data.frame(
        title = trimws(title),
        date = as.Date(format(when, tz = SYD_TZ)))
    }
  }
  if (length(rows) == 0) return(NULL)
  out <- unique(do.call(rbind, rows))
  out[order(out$date), ]
}

#' Upcoming releases relevant to the model: scraped if possible, else
#' rule-based estimates flagged `estimated = TRUE`.
upcoming_releases <- function(today = ausnow_today(), n = 5) {
  cal <- tryCatch(fetch_release_calendar(), error = function(e) NULL)
  if (!is.null(cal)) {
    pat <- paste(CAL_WATCH, collapse = "|")
    hit <- cal[grepl(pat, cal$title, ignore.case = TRUE) & cal$date >= today, ]
    if (nrow(hit) >= 1) {
      hit <- utils::head(hit[order(hit$date), ], n)
      hit$estimated <- FALSE
      return(hit)
    }
  }
  log_msg("WARN calendar: scrape failed or empty — using rule-based estimates")
  est <- estimate_release_dates(today)
  est <- utils::head(est[est$date >= today, ][order(est$date[est$date >= today]), ], n)
  est$estimated <- TRUE
  est
}

#' Crude rule-based schedule: monthly indicators on typical day-of-month,
#' quarterly on the GDP-cycle pattern. Used only when the scrape fails.
estimate_release_dates <- function(today) {
  mk <- function(title, day, months = 1:12) {
    dates <- as.Date(sapply(0:2, function(k) {
      m <- as.integer(format(today, "%m")) - 1 + k
      y <- as.integer(format(today, "%Y")) + m %/% 12
      sprintf("%d-%02d-%02d", y, m %% 12 + 1, day)
    }))
    data.frame(title = title, date = dates)[as.integer(format(dates, "%m")) %in% months, ]
  }
  rbind(
    mk("Labour Force, Australia (estimated)", 15),
    mk("Monthly Household Spending Indicator (estimated)", 5),
    mk("International Trade in Goods (estimated)", 5),
    mk("Building Approvals, Australia (estimated)", 3),
    mk("Monthly CPI (estimated)", 25),
    mk("National Accounts (GDP) (estimated)", 3, months = c(3, 6, 9, 12))
  )
}
