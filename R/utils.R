# Shared helpers: dates, quarters, logging.

SYD_TZ <- "Australia/Sydney"

#' Today's date in Sydney, overridable for testing/simulation via AUSNOW_TODAY.
ausnow_today <- function() {
  mock <- Sys.getenv("AUSNOW_TODAY", "")
  if (nzchar(mock)) return(as.Date(mock))
  as.Date(format(Sys.time(), tz = SYD_TZ))
}

#' Quarter label like "2026Q1" from a Date (any day in the quarter).
quarter_label <- function(date) {
  paste0(format(date, "%Y"), "Q", (as.integer(format(date, "%m")) - 1L) %/% 3L + 1L)
}

#' First day of the quarter for a quarter label.
quarter_start <- function(qlab) {
  y <- as.integer(substr(qlab, 1, 4))
  q <- as.integer(substr(qlab, 6, 6))
  as.Date(sprintf("%d-%02d-01", y, (q - 1L) * 3L + 1L))
}

#' Last day of the quarter.
quarter_end <- function(qlab) {
  add_quarters(quarter_start(qlab), 1L) - 1L
}

#' Shift the first-of-quarter date by n quarters.
add_quarters <- function(date, n) {
  m <- as.integer(format(date, "%m")) - 1L + 3L * n
  y <- as.integer(format(date, "%Y")) + m %/% 12L
  as.Date(sprintf("%d-%02d-01", y, m %% 12L + 1L))
}

#' Shift a quarter label by n quarters.
shift_quarter <- function(qlab, n) quarter_label(add_quarters(quarter_start(qlab), n))

#' ABS quarterly data uses the first month of the quarter as the date stamp
#' (e.g. 2026-03-01 = 2026Q1 in 5206.0). Middle-month stamps (vacancies) also
#' map correctly because quarter_label only needs any day inside the quarter.
date_to_quarter <- function(date) quarter_label(date)

#' Scheduled ABS GDP release date for a target quarter: first Wednesday of the
#' third month after quarter end (Mar/Jun/Sep/Dec), per the ABS release pattern.
gdp_release_date <- function(qlab) {
  m1 <- add_quarters(quarter_start(qlab), 1L)        # first day of next quarter
  rel_month <- as.Date(format(m1 + 62, "%Y-%m-01"))  # third month after quarter end
  d <- rel_month
  while (format(d, "%u") != "3") d <- d + 1
  d
}

log_msg <- function(...) {
  cat(format(Sys.time(), "%H:%M:%S"), "|", sprintf(...), "\n")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

#' Quarter-over-quarter growth (%) of the mean of monthly values, per quarter.
#' Input: data.frame(date, value) monthly. Output: data.frame(quarter, growth).
monthly_to_q_growth <- function(df) {
  df <- df[!is.na(df$value), ]
  if (nrow(df) == 0) return(data.frame(quarter = character(), growth = numeric()))
  df$quarter <- date_to_quarter(df$date)
  agg <- stats::aggregate(value ~ quarter, df, mean)
  agg <- agg[order(agg$quarter), ]
  data.frame(
    quarter = agg$quarter[-1],
    growth  = 100 * (agg$value[-1] / agg$value[-nrow(agg)] - 1)
  )
}

#' AR(1) fill: extend a monthly series to cover all months of `through_quarter`.
#' Fits AR(1) on m/m log-growth; returns the completed data.frame(date, value).
ar_fill_months <- function(df, through_quarter) {
  df <- df[!is.na(df$value), ]
  df <- df[order(df$date), ]
  end_date <- quarter_end(through_quarter)
  last <- max(df$date)
  if (last >= as.Date(format(end_date, "%Y-%m-01"))) return(df)
  g <- diff(log(pmax(df$value, 1e-9)))
  g <- utils::tail(g, 60)
  phi <- 0; mu <- mean(g)
  if (length(g) >= 12) {
    fit <- tryCatch(stats::ar(g, order.max = 1, aic = FALSE, method = "yule-walker"),
                    error = function(e) NULL)
    if (!is.null(fit) && length(fit$ar) == 1) { phi <- fit$ar; mu <- fit$x.mean }
  }
  gp <- utils::tail(g, 1)
  val <- utils::tail(df$value, 1)
  d <- last
  out <- df
  while (d < as.Date(format(end_date, "%Y-%m-01"))) {
    d <- as.Date(format(d + 35, "%Y-%m-01"))
    gp <- mu + phi * (gp - mu)
    val <- val * exp(gp)
    out <- rbind(out, data.frame(date = d, value = val))
    if (d > end_date) break
  }
  out
}

#' AR(1) forecast of next value of a quarterly growth series (numeric vector).
ar1_forecast <- function(x, h = 1) {
  x <- x[!is.na(x)]
  if (length(x) < 8) return(rep(mean(x) %||% 0, h))
  fit <- tryCatch(stats::ar(x, order.max = 1, aic = FALSE, method = "yule-walker"),
                  error = function(e) NULL)
  if (is.null(fit) || length(fit$ar) != 1) return(rep(mean(x), h))
  mu <- fit$x.mean; phi <- fit$ar
  out <- numeric(h); prev <- utils::tail(x, 1)
  for (i in seq_len(h)) { prev <- mu + phi * (prev - mu); out[i] <- prev }
  out
}
