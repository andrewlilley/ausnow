test_that("upsert_csv is idempotent on its key columns", {
  tmp <- tempfile(fileext = ".csv")
  rows <- data.frame(run_date = "2026-06-10", target_quarter = "2026Q2", blend = 0.5)
  upsert_csv(tmp, rows, c("run_date", "target_quarter"))
  upsert_csv(tmp, rows, c("run_date", "target_quarter"))
  expect_equal(nrow(utils::read.csv(tmp)), 1)
  # same key, new value replaces
  rows$blend <- 0.7
  upsert_csv(tmp, rows, c("run_date", "target_quarter"))
  got <- utils::read.csv(tmp)
  expect_equal(nrow(got), 1)
  expect_equal(as.numeric(got$blend), 0.7)
  # different key appends
  rows$run_date <- "2026-06-11"
  upsert_csv(tmp, rows, c("run_date", "target_quarter"))
  expect_equal(nrow(utils::read.csv(tmp)), 2)
  unlink(tmp)
})

with_mocked_fetch <- function(mock, code) {
  real <- get("fetch_source", envir = globalenv())
  assign("fetch_source", mock, envir = globalenv())
  on.exit(assign("fetch_source", real, envir = globalenv()), add = TRUE)
  force(code)
}

test_that("fetch failure degrades to previous vintage and is flagged", {
  v_prev <- make_synthetic_vintage()
  with_mocked_fetch(function(key, spec) {
    if (key == "hours") stop("simulated network failure")
    v_prev$data[[key]] %||% stop("no data")
  }, {
    res <- fetch_all(prev = v_prev, keys = c("hours", "mhsi"))
    expect_true("hours" %in% names(res$data))       # degraded copy present
    expect_equal(res$data$hours, v_prev$data$hours)
    st <- res$status
    expect_false(st$ok[st$key == "hours"])
    expect_true(st$stale[st$key == "hours"])
    expect_true(st$ok[st$key == "mhsi"])
  })
})

test_that("fetch failure with no previous vintage does not kill the run", {
  with_mocked_fetch(function(key, spec) stop("offline"), {
    res <- fetch_all(prev = NULL, keys = c("hours"))
    expect_equal(length(res$data), 0)
    expect_false(res$status$ok[1])
  })
})

test_that("vintage save/load/diff round-trips", {
  v <- make_synthetic_vintage()
  dir <- file.path(tempdir(), "vintroot")
  old_paths <- PATHS
  PATHS$vintages <<- file.path(dir, "vintages")
  on.exit(PATHS <<- old_paths, add = TRUE)
  save_vintage(v, as.Date("2026-06-09"))
  prev <- load_prev_vintage(as.Date("2026-06-10"))
  expect_false(is.null(prev))
  expect_setequal(names(prev$data), names(v$data))
  expect_equal(nrow(detect_releases(v, prev)) %||% 0, 0)   # identical content
  # same-day rerun must not see its own snapshot as "previous"
  save_vintage(v, as.Date("2026-06-10"))
  prev2 <- load_prev_vintage(as.Date("2026-06-10"))
  expect_equal(basename(prev2$dir), "2026-06-09")
})

test_that("final errors are recorded once per retired quarter", {
  old_paths <- PATHS
  dir <- file.path(tempdir(), paste0("state", as.integer(stats::runif(1, 1e6, 1e7))))
  dir.create(dir, recursive = TRUE)
  PATHS$history <<- file.path(dir, "h.csv")
  PATHS$errors <<- file.path(dir, "e.csv")
  on.exit(PATHS <<- old_paths, add = TRUE)
  v <- make_synthetic_vintage()
  gdp_g <- q_growth(get_series(v$data, "gdp_cvm"))
  q_last <- utils::tail(gdp_g$quarter, 1)
  hist_rows <- data.frame(
    run_date = c("2026-05-01", "2026-06-01"), target_quarter = q_last,
    blend = c(0.4, 0.5), labour_read = c(0.45, 0.52), expenditure_read = c(0.35, 0.48))
  utils::write.csv(hist_rows, PATHS$history, row.names = FALSE)
  record_final_errors(v$data, as.Date("2026-06-10"))
  errs <- utils::read.csv(PATHS$errors)
  expect_equal(nrow(errs), 1)
  actual <- gdp_g$g[gdp_g$quarter == q_last]
  expect_equal(errs$err_blend, round(0.5 - actual, 4), tolerance = 1e-6)
  # running again must not duplicate
  record_final_errors(v$data, as.Date("2026-06-11"))
  expect_equal(nrow(utils::read.csv(PATHS$errors)), 1)
})

test_that("pseudo-real-time truncation respects publication lags", {
  v <- make_synthetic_vintage()
  asof <- as.Date("2025-11-15")
  t <- truncate_asof(v$data, asof)
  # hours (lag 14): October data (period end 31 Oct, published 14 Nov) is in
  expect_equal(max(t$hours$date), as.Date("2025-10-01"))
  # mhsi (lag 35): September is in, October (4 Dec) is not
  expect_equal(max(t$mhsi$date), as.Date("2025-09-01"))
  # national accounts: 2025Q2 (released 3 Sep) in, 2025Q3 (3 Dec) out
  expect_equal(quarter_label(max(t$natacc$date)), "2025Q2")
  # the day before vs the day of a GDP release flips availability
  t2 <- truncate_asof(v$data, as.Date("2025-12-02"))
  t3 <- truncate_asof(v$data, as.Date("2025-12-03"))
  expect_equal(quarter_label(max(t2$natacc$date)), "2025Q2")
  expect_equal(quarter_label(max(t3$natacc$date)), "2025Q3")
})
