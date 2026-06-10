# Synthetic vintage generator: plausible random-walk series for every
# configured indicator so the full model stack runs hermetically (no network).

synth_series <- function(id, label, start, freq = "M", n = NULL, level0 = 100,
                         drift = 0.003, sd = 0.006, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  dates <- if (freq == "M") seq(as.Date(start), as.Date("2026-05-01"), by = "month")
           else seq(as.Date(start), as.Date("2026-01-01"), by = "3 months")
  if (!is.null(n)) dates <- utils::tail(dates, n)
  vals <- level0 * exp(cumsum(stats::rnorm(length(dates), drift, sd)))
  data.frame(series_id = id, series = label, date = dates, value = vals)
}

make_synthetic_vintage <- function(seed = 42, through = "2026-05-01") {
  set.seed(seed)
  d <- list()
  q <- function(id, lab, lvl, drift = 0.005, sd = 0.004)
    synth_series(id, lab, "2002-03-01", "Q", level0 = lvl, drift = drift, sd = sd)
  natacc <- rbind(
    q("A2304402X", "GDP", 600000), q("A2304081W", "HFCE", 300000),
    q("A2304098T", "Dwellings", 30000), q("A2304099V", "OTC", 10000),
    q("A2304095K", "Business inv", 70000), q("A2304080V", "Public cons", 130000),
    q("A2304109L", "Public inv", 30000), q("A2304114F", "Exports", 130000),
    q("A2304115J", "Imports", 130000))
  contrib <- data.frame(
    series_id = "A2304020T", series = "Inventories contribution",
    date = seq(as.Date("2002-03-01"), as.Date("2026-01-01"), by = "3 months"))
  contrib$value <- stats::rnorm(nrow(contrib), 0, 0.15)
  disc <- contrib; disc$series_id <- "A2304028K"; disc$series <- "Discrepancy contribution"
  disc$value <- stats::rnorm(nrow(disc), 0, 0.05)
  d$natacc <- rbind(natacc, contrib, disc)

  d$hours <- synth_series("A84426277X", "Hours", "2002-01-01", "M", level0 = 1800, drift = 0.001, sd = 0.004)
  d$lfs <- rbind(
    synth_series("A84423043C", "Employed", "2002-01-01", "M", level0 = 13000, drift = 0.0015, sd = 0.002),
    synth_series("A84423050A", "Participation", "2002-01-01", "M", level0 = 66, drift = 0, sd = 0.001))
  d$mhsi <- synth_series("A130200584T", "MHSI total", "2019-01-01", "M", level0 = 70000, drift = 0.004, sd = 0.008)
  d$trade <- rbind(
    synth_series("A2718577A", "Goods credits", "2005-01-01", "M", level0 = 30000, drift = 0.004, sd = 0.03),
    synth_series("A2718603V", "Goods debits", "2005-01-01", "M", level0 = 28000, drift = 0.004, sd = 0.025))
  d$approvals <- synth_series("A422070J", "Dwellings approved", "2002-01-01", "M", level0 = 15000, drift = 0, sd = 0.05)
  d$construction <- rbind(
    q("A405136V", "Building work", 30000, sd = 0.02), q("A405154X", "Engineering work", 25000, sd = 0.025),
    q("A405118R", "Private constr", 40000, sd = 0.02))
  d$capex <- rbind(q("A124797537K", "Capex total", 35000, sd = 0.02),
                   q("A124797536J", "Capex equip", 15000, sd = 0.02),
                   q("A124797535F", "Capex b&s", 20000, sd = 0.02))
  d$busind <- q("A3538852F", "Inventories level", 170000, drift = 0.002, sd = 0.01)
  d$bop <- rbind(q("A3535542V", "BoP credits CVM", 120000, sd = 0.02),
                 q("A3535543W", "BoP debits CVM", 115000, sd = 0.02))
  d$cpi <- synth_series("A130393720C", "CPI monthly", "2024-04-01", "M", level0 = 140, drift = 0.0025, sd = 0.001)
  d$cpi_old <- synth_series("A128478317T", "CPI indicator", "2017-09-01", "M", level0 = 110, drift = 0.0025, sd = 0.001)
  d$vacancies <- q("A590698F", "Vacancies", 250, drift = 0, sd = 0.04)
  d$gfs <- q("GFS_PUBDEM", "GFS public demand", 150000, drift = 0.006, sd = 0.008)
  d$rba_credit <- synth_series("DSYNTH1", "Credit; Business; Seasonally adjusted",
                               "2002-01-01", "M", level0 = 1000, drift = 0.004, sd = 0.004)
  status <- do.call(rbind, lapply(names(d), function(k)
    data.frame(key = k, ok = TRUE, stale = FALSE, note = "synthetic",
               latest = max(d[[k]]$date))))
  list(data = d, status = status)
}

#' A vintage extended by one new month of data for given keys (a "release").
advance_vintage <- function(v, keys, bump = 0.01) {
  out <- v
  for (k in keys) {
    df <- out$data[[k]]
    for (sid in unique(df$series_id)) {
      s <- df[df$series_id == sid, ]
      s <- s[order(s$date), ]
      last <- s[nrow(s), ]
      freq_m <- INDICATORS[[k]]$freq %||% "M"
      nd <- if (freq_m == "Q") add_quarters(as.Date(format(last$date, "%Y-%m-01")), 1)
            else as.Date(format(as.Date(format(last$date, "%Y-%m-01")) + 32, "%Y-%m-01"))
      newrow <- data.frame(series_id = sid, series = last$series, date = nd,
                           value = if (abs(last$value) < 5) last$value else last$value * (1 + bump))
      out$data[[k]] <- rbind(df, newrow)
    }
  }
  out
}
