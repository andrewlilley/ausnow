# Models: labour read, expenditure bridge read, blend.
#
# Everything below consumes a `data` object (named list of series data.frames,
# i.e. vintage$data) and is deterministic given that object — the attribution
# engine relies on this: impact of a release = f(with) - f(without).

suppressMessages(library(dplyr))

#' Extract one configured series as data.frame(date, value), sorted.
get_series <- function(data, skey) {
  cfg <- SERIES[[skey]]
  df <- data[[cfg$key]]
  if (is.null(df)) return(NULL)
  out <- df[df$series_id == cfg$id, c("date", "value")]
  out <- out[!is.na(out$value), ]
  if (nrow(out) == 0) return(NULL)
  out <- out[order(out$date), ]
  out[!duplicated(out$date), ]   # same id can appear in several ABS tables
}

#' Business credit (m/m growth-able level) from RBA D2 by name matching.
get_rba_business_credit <- function(data) {
  df <- data$rba_credit
  if (is.null(df)) return(NULL)
  hit <- df[grepl("business", df$series, ignore.case = TRUE) &
            grepl("credit", df$series, ignore.case = TRUE) &
            !grepl("growth|change", df$series, ignore.case = TRUE), ]
  if (nrow(hit) == 0) return(NULL)
  sid <- names(sort(table(hit$series_id), decreasing = TRUE))[1]
  out <- hit[hit$series_id == sid, c("date", "value")]
  out[order(out$date), ]
}

#' Restrict a vintage to what would have been published by `asof`
#' (pseudo-real-time availability; see DECISIONS.md D8).
truncate_asof <- function(data, asof) {
  out <- list()
  for (key in names(data)) {
    lag <- INDICATORS[[key]]$pub_lag_days %||% 35
    df <- data[[key]]
    if (is.null(df) || nrow(df) == 0) { out[key] <- list(df); next }
    if (key == "natacc") {
      # exact rule: quarter Q is available from its scheduled release date
      rel <- as.Date(vapply(df$date, function(d)
        as.character(gdp_release_date(quarter_label(d))), ""))
      out[[key]] <- df[rel <= asof, , drop = FALSE]
      next
    }
    period_end <- if ((INDICATORS[[key]]$freq %||% "M") == "Q") {
      as.Date(vapply(df$date, function(d) as.character(quarter_end(quarter_label(d))), ""))
    } else {
      fom <- as.Date(format(df$date, "%Y-%m-01"))
      as.Date(format(fom + 32, "%Y-%m-01")) - 1   # end of month
    }
    out[[key]] <- df[period_end + lag <= asof, , drop = FALSE]
  }
  out
}

#' Monthly CPI deflator: new monthly CPI (6401, from Apr 2024) ratio-spliced
#' onto the discontinued Monthly CPI Indicator (6484, Sep 2017 - Sep 2025).
monthly_cpi_deflator <- function(data) {
  new <- get_series(data, "cpi_all")
  old <- get_series(data, "cpi_old_all")
  if (is.null(new) && is.null(old)) return(NULL)
  if (is.null(old)) return(new)
  if (is.null(new)) return(old)
  overlap <- merge(new, old, by = "date", suffixes = c("_new", "_old"))
  if (nrow(overlap) >= 3) {
    ratio <- mean(overlap$value_new / overlap$value_old)
    old$value <- old$value * ratio
  }
  spliced <- rbind(old[old$date < min(new$date), ], new)
  spliced[order(spliced$date), ]
}

# ---- quarterly frame -------------------------------------------------------

#' Quarterly growth (%) of a quarterly-level series.
q_growth <- function(df) {
  if (is.null(df) || nrow(df) < 2) return(data.frame(quarter = character(), g = numeric()))
  df <- df[order(df$date), ]
  data.frame(quarter = quarter_label(df$date[-1]),
             g = 100 * (df$value[-1] / df$value[-nrow(df)] - 1))
}

#' Build the quarterly regression frame from a data vintage.
#' target_q: monthly regressors are AR-filled through this quarter.
build_qframe <- function(data, target_q) {
  qcol <- function(df, name) {
    if (is.null(df) || nrow(df) == 0)
      return(data.frame(quarter = character(), v = numeric()) |> stats::setNames(c("quarter", name)))
    stats::setNames(df, c("quarter", name))
  }
  m_growth <- function(skey, deflate_cpi = FALSE) {
    df <- get_series(data, skey)
    if (is.null(df)) return(NULL)
    if (deflate_cpi) {
      cpi <- monthly_cpi_deflator(data)
      if (!is.null(cpi)) {
        mm <- merge(df, cpi, by = "date", suffixes = c("", "_cpi"))
        if (nrow(mm) >= 24) df <- data.frame(date = mm$date, value = mm$value / mm$value_cpi)
      }
    }
    qg <- monthly_to_q_growth(ar_fill_months(df, target_q))
    # Ragged-edge shrinkage (DECISIONS.md D19): with only 1-2 months of the
    # target quarter observed, the AR month-fill propagates single-month noise
    # into the quarterly aggregate while bridge betas assume a full quarter.
    # Shrink the partial-quarter estimate toward the no-in-quarter-data fill in
    # proportion to the unobserved share.
    m_obs <- sum(quarter_label(df$date) == target_q & !is.na(df$value))
    if (m_obs >= 1 && m_obs <= 2) {
      df0 <- df[quarter_label(df$date) != target_q, , drop = FALSE]
      qg0 <- monthly_to_q_growth(ar_fill_months(df0, target_q))
      i <- qg$quarter == target_q; i0 <- qg0$quarter == target_q
      if (any(i) && any(i0)) {
        sh <- m_obs / 3
        qg$growth[i] <- qg0$growth[i0] + sh * (qg$growth[i] - qg0$growth[i0])
      }
    }
    qg
  }
  q_growth_filled <- function(skey) {
    df <- get_series(data, skey)
    if (is.null(df)) return(NULL)
    qg <- q_growth(df)
    # AR-fill forward to target quarter
    if (nrow(qg) > 0) {
      last_q <- qg$quarter[nrow(qg)]
      while (last_q < target_q) {
        last_q <- shift_quarter(last_q, 1)
        qg <- rbind(qg, data.frame(quarter = last_q, g = ar1_forecast(qg$g, 1)))
      }
    }
    qg
  }

  frames <- list()
  add <- function(nm, df) { if (!is.null(df) && nrow(df) > 0) frames[[nm]] <<- qcol(df, nm) }

  # --- targets (published national accounts) ---
  for (sk in c("gdp_cvm", "hfce_cvm", "dwell_cvm", "otc_cvm", "businv_cvm",
               "pubcons_cvm", "pubinv_cvm", "exports_cvm", "imports_cvm")) {
    nm <- paste0("g_", sub("_cvm", "", sk))
    add(nm, q_growth(get_series(data, sk)))
  }
  for (sk in c("inv_contrib", "disc_contrib")) {
    df <- get_series(data, sk)
    if (!is.null(df)) add(sub("_contrib", "_c", sk),
                          data.frame(quarter = quarter_label(df$date), g = df$value))
  }

  # --- monthly regressors (AR-filled through target quarter) ---
  add("x_hours",      m_growth("hours_idx"))
  add("x_employed",   m_growth("employed"))
  add("x_mhsi_real",  m_growth("mhsi_total", deflate_cpi = TRUE))
  add("x_trade_cred", m_growth("trade_credits"))
  add("x_trade_deb",  m_growth("trade_debits"))
  add("x_approvals",  m_growth("approvals_tot"))

  cred <- get_rba_business_credit(data)
  if (!is.null(cred)) add("x_buscred", monthly_to_q_growth(ar_fill_months(cred, target_q)))

  # --- quarterly partial regressors (AR-filled at quarterly level) ---
  add("x_constr_bldg", q_growth_filled("constr_bldg"))
  add("x_constr_eng",  q_growth_filled("constr_eng"))
  add("x_capex",       q_growth_filled("capex_tot"))
  add("x_capex_eqp",   q_growth_filled("capex_eqp"))
  add("x_bop_cred",    q_growth_filled("bop_credits"))
  add("x_bop_deb",     q_growth_filled("bop_debits"))
  add("x_gfs",         q_growth_filled("gfs_pubdem"))
  add("x_vacancies",   q_growth_filled("vacancies_aus"))

  # inventories: second difference of business-indicators inventories, scaled
  # by lagged GDP level (proxy for the national-accounts contribution).
  bi <- get_series(data, "busind_inv"); gdp <- get_series(data, "gdp_cvm")
  if (!is.null(bi) && !is.null(gdp) && nrow(bi) > 3) {
    bi <- bi[order(bi$date), ]
    d1 <- diff(bi$value); d2 <- diff(d1)
    qx <- quarter_label(bi$date[-(1:2)])
    gdpq <- stats::setNames(gdp$value, quarter_label(gdp$date))
    denom <- gdpq[vapply(qx, shift_quarter, "", n = -1)]
    xinv <- data.frame(quarter = qx, g = 100 * d2 / as.numeric(denom))
    xinv <- xinv[!is.na(xinv$g), ]
    # AR-fill to target quarter
    if (nrow(xinv) > 0) {
      lq <- xinv$quarter[nrow(xinv)]
      while (lq < target_q) {
        lq <- shift_quarter(lq, 1)
        xinv <- rbind(xinv, data.frame(quarter = lq, g = ar1_forecast(xinv$g, 1)))
      }
    }
    add("x_busind_inv", xinv)
  }

  # NAB: quarterly average level of conditions; quarterly change in cap util.
  nab <- data$nab
  if (!is.null(nab) && nrow(nab) > 0) {
    for (pair in list(c("NAB_CONDITIONS", "x_nab_cond"), c("NAB_CAPUTIL", "x_nab_capu"))) {
      s <- nab[nab$series_id == pair[1], c("date", "value")]
      if (nrow(s) >= 8) {
        s$quarter <- quarter_label(s$date)
        agg <- stats::aggregate(value ~ quarter, s, mean)
        agg <- agg[order(agg$quarter), ]
        if (pair[1] == "NAB_CAPUTIL") {
          if (nrow(agg) > 1)
            add(pair[2], data.frame(quarter = agg$quarter[-1], g = diff(agg$value)))
        } else {
          add(pair[2], data.frame(quarter = agg$quarter, g = agg$value))
        }
      }
    }
  }

  qf <- Reduce(function(a, b) merge(a, b, by = "quarter", all = TRUE), frames)
  qf[order(qf$quarter), ]
}

# ---- labour read -----------------------------------------------------------

#' GDP growth ~ hours growth + productivity trend.
labour_read <- function(data, target_q) {
  hours <- get_series(data, "hours_idx")
  gdp_g <- q_growth(get_series(data, "gdp_cvm"))
  if (is.null(hours) || nrow(gdp_g) < 12) return(NULL)

  months_obs <- sum(quarter_label(hours$date) == target_q)
  hq <- monthly_to_q_growth(ar_fill_months(hours, target_q))
  h_target <- hq$growth[hq$quarter == target_q]
  if (length(h_target) == 0) return(NULL)

  # productivity trend: rolling mean of (gdp growth - hours growth) over the
  # last 20 published quarters
  names(hq) <- c("quarter", "g_h")
  joint <- merge(stats::setNames(gdp_g, c("quarter", "g_gdp")), hq, by = "quarter")
  joint <- joint[order(joint$quarter), ]
  resid <- joint$g_gdp - joint$g_h
  prod_trend <- mean(utils::tail(resid[!is.na(resid)], 20))

  # cyclical adjustment from NAB capacity utilisation when available: estimate
  # by OLS of the productivity residual on the change in cap util
  adj <- 0
  nab <- data$nab
  if (!is.null(nab) && any(nab$series_id == "NAB_CAPUTIL")) {
    cu <- nab[nab$series_id == "NAB_CAPUTIL", c("date", "value")]
    cu$quarter <- quarter_label(cu$date)
    cuq <- stats::aggregate(value ~ quarter, cu, mean)
    cuq <- cuq[order(cuq$quarter), ]
    if (nrow(cuq) > 13) {
      dcu <- data.frame(quarter = cuq$quarter[-1], dcu = diff(cuq$value))
      jj <- merge(data.frame(quarter = joint$quarter, r = resid), dcu, by = "quarter")
      if (nrow(jj) >= 12 && stats::sd(jj$dcu) > 0) {
        beta <- stats::coef(stats::lm(r ~ dcu, jj))[["dcu"]]
        dcu_t <- dcu$dcu[dcu$quarter == target_q]
        if (length(dcu_t) == 1 && is.finite(beta)) adj <- beta * dcu_t
      }
    }
  }

  list(estimate = h_target + prod_trend + adj,
       hours_growth = h_target, prod_trend = prod_trend, nab_adjust = adj,
       months_observed = months_obs)
}

# ---- expenditure read ------------------------------------------------------

BRIDGES <- list(
  hfce        = list(y = "g_hfce",    x = c("x_mhsi_real", "x_nab_cond")),
  dwell       = list(y = "g_dwell",   x = c("x_approvals_l1", "x_constr_bldg")),
  otc         = list(y = "g_otc",     x = character(0)),
  businv      = list(y = "g_businv",  x = c("x_capex", "x_constr_eng", "x_nab_capu")),
  pubcons     = list(y = "g_pubcons", x = c("x_gfs")),
  pubinv      = list(y = "g_pubinv",  x = c("x_gfs")),
  exports     = list(y = "g_exports", x = c("x_bop_cred", "x_trade_cred")),
  imports     = list(y = "g_imports", x = c("x_bop_deb", "x_trade_deb")),
  inventories = list(y = "inv_c",     x = c("x_busind_inv")),
  discrepancy = list(y = "disc_c",    x = character(0))
)
MIN_BRIDGE_OBS <- 16
MAX_WINDOW_Q   <- 60

#' Estimate one bridge and predict the target quarter.
#' Returns list(pred, method, n_obs).
bridge_predict <- function(qf, spec, target_q, last_published_q) {
  y <- spec$y
  if (!y %in% names(qf)) return(list(pred = 0, method = "none", n = 0))
  est <- qf[qf$quarter <= last_published_q & !is.na(qf[[y]]), , drop = FALSE]
  est <- utils::tail(est, MAX_WINDOW_Q)
  xs <- intersect(spec$x, names(qf))
  xs <- xs[vapply(xs, function(v) {
    ok <- sum(!is.na(est[[v]]) & !is.na(est[[y]]))
    ok >= MIN_BRIDGE_OBS && !is.na(qf[[v]][qf$quarter == target_q][1])
  }, logical(1))]
  row_t <- qf[qf$quarter == target_q, , drop = FALSE]
  if (length(xs) > 0 && nrow(row_t) == 1) {
    dat <- est[, c(y, xs), drop = FALSE]
    dat <- dat[stats::complete.cases(dat), , drop = FALSE]
    if (nrow(dat) >= MIN_BRIDGE_OBS) {
      fml <- stats::as.formula(paste(y, "~", paste(xs, collapse = "+")))
      fit <- stats::lm(fml, dat)
      pred <- stats::predict(fit, newdata = row_t)
      if (is.finite(pred)) return(list(pred = as.numeric(pred),
                                       method = paste("bridge:", paste(xs, collapse = "+")),
                                       n = nrow(dat)))
    }
  }
  # AR fallback on the target series itself
  hist <- est[[y]]
  steps <- quarter_diff(target_q, last_published_q)
  pred <- utils::tail(ar1_forecast(hist, max(steps, 1)), 1)
  list(pred = pred, method = "ar1", n = sum(!is.na(hist)))
}

quarter_diff <- function(q2, q1) {
  y2 <- as.integer(substr(q2, 1, 4)); k2 <- as.integer(substr(q2, 6, 6))
  y1 <- as.integer(substr(q1, 1, 4)); k1 <- as.integer(substr(q1, 6, 6))
  (y2 - y1) * 4L + (k2 - k1)
}

#' Bottom-up expenditure read for one target quarter.
expenditure_read <- function(data, target_q, qf = NULL) {
  gdp <- get_series(data, "gdp_cvm")
  if (is.null(gdp) || nrow(gdp) < 20) return(NULL)
  last_pub <- quarter_label(max(gdp$date))
  if (is.null(qf)) qf <- build_qframe(data, target_q)
  if (!"x_approvals" %in% names(qf)) qf$x_approvals <- NA_real_
  qf$x_approvals_l1 <- c(NA, qf$x_approvals[-nrow(qf)])

  # weights: average CVM share of GDP over the last 4 published quarters
  wt <- function(level_key, negate = FALSE) {
    lv <- get_series(data, level_key)
    mm <- merge(lv, gdp, by = "date", suffixes = c("", "_gdp"))
    w <- mean(utils::tail(mm$value / mm$value_gdp, 4))
    if (negate) -w else w
  }

  comps <- list(); total <- 0
  for (cn in names(COMPONENTS)) {
    cc <- COMPONENTS[[cn]]
    bp <- bridge_predict(qf, BRIDGES[[cn]], target_q, last_pub)
    if (cc$mode == "level") {
      w <- wt(cc$level, isTRUE(cc$negate))
      contrib <- w * bp$pred
    } else {
      contrib <- bp$pred
      w <- NA_real_
    }
    comps[[cn]] <- data.frame(component = cn, label = cc$label, growth = bp$pred,
                              weight = w, contribution = contrib, method = bp$method)
    total <- total + contrib
  }
  comps <- bind_rows(comps)

  # bias correction: mean gap between actual GDP growth and the in-sample
  # bottom-up sum over the last 12 published quarters
  bias <- bottomup_bias(qf, data, last_pub)
  list(estimate = total + bias, raw_sum = total, bias = bias,
       components = comps, last_published = last_pub, qframe = qf)
}

bottomup_bias <- function(qf, data, last_pub, nq = 12) {
  gdp <- get_series(data, "gdp_cvm")
  need <- c("g_gdp", "g_hfce", "g_dwell", "g_otc", "g_businv", "g_pubcons",
            "g_pubinv", "g_exports", "g_imports", "inv_c", "disc_c")
  if (!all(need %in% names(qf))) return(0)
  est <- qf[qf$quarter <= last_pub, need]
  est <- utils::tail(est[stats::complete.cases(est), ], nq)
  if (nrow(est) < 4) return(0)
  gdpq <- stats::setNames(gdp$value, quarter_label(gdp$date))
  # recompute weights per quarter would be exact; constant recent weights are
  # close enough for a bias term
  w <- list()
  for (cn in names(COMPONENTS)) {
    cc <- COMPONENTS[[cn]]
    if (cc$mode != "level") next
    lv <- get_series(data, cc$level)
    mm <- merge(lv, gdp, by = "date", suffixes = c("", "_gdp"))
    w[[cn]] <- mean(utils::tail(mm$value / mm$value_gdp, 4)) * (if (isTRUE(cc$negate)) -1 else 1)
  }
  bottomup <- with(est, w$hfce * g_hfce + w$dwell * g_dwell + w$otc * g_otc +
                   w$businv * g_businv + w$pubcons * g_pubcons + w$pubinv * g_pubinv +
                   w$exports * g_exports + w$imports * g_imports + inv_c + disc_c)
  mean(est$g_gdp - bottomup)
}

# ---- blend -----------------------------------------------------------------

#' Weight on the labour read as a function of days until the GDP release.
#' Uses the backtest-estimated path if present, else a sensible default.
blend_weight <- function(days_to_release, weights_path = PATHS$weights) {
  if (file.exists(weights_path)) {
    w <- utils::read.csv(weights_path)
    if (nrow(w) >= 2) {
      return(stats::approx(w$days_to_release, w$w_labour, xout = days_to_release,
                           rule = 2)$y)
    }
  }
  # default: labour-heavy early, expenditure-dominant by partials week
  pmin(0.95, pmax(0.05, 1 / (1 + exp(-(days_to_release - 45) / 15)) * 0.9 + 0.05))
}

#' Uncertainty band (+/- pp, 80%) by days to release, from backtest summary.
uncertainty_band <- function(days_to_release, summary_path = PATHS$backtest) {
  if (file.exists(summary_path)) {
    s <- utils::read.csv(summary_path)
    s <- s[s$model == "blend", ]
    if (nrow(s) >= 2) {
      rmse <- stats::approx(s$days_to_release, s$rmse, xout = days_to_release,
                            rule = 2)$y
      return(1.28 * rmse)
    }
  }
  0.25 + 0.35 * pmin(1, days_to_release / 120)
}

#' Full nowcast for one target quarter. The single function the attribution
#' engine calls: deterministic in (data, target_q, asof).
nowcast_quarter <- function(data, target_q, asof) {
  rel_date <- gdp_release_date(target_q)
  dtr <- as.numeric(rel_date - asof)
  lab <- labour_read(data, target_q)
  exp <- expenditure_read(data, target_q)
  if (is.null(exp) && is.null(lab)) return(NULL)
  w <- blend_weight(dtr)
  if (is.null(lab)) w <- 0
  if (is.null(exp)) w <- 1
  blend <- w * (lab$estimate %||% 0) + (1 - w) * (exp$estimate %||% 0)
  months_obs <- lab$months_observed %||% 0
  band <- uncertainty_band(dtr)
  list(target_quarter = target_q, asof = asof,
       blend = blend, labour = lab$estimate %||% NA_real_,
       expenditure = exp$estimate %||% NA_real_,
       w_labour = w, days_to_release = dtr, release_date = rel_date,
       band = band,
       model_only = months_obs == 0 && asof <= quarter_end(target_q),
       months_observed = months_obs,
       labour_detail = lab, exp_detail = exp)
}
