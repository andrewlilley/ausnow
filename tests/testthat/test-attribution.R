test_that("nowcast runs on a synthetic vintage", {
  v <- make_synthetic_vintage()
  nc <- nowcast_quarter(v$data, "2026Q2", as.Date("2026-06-10"))
  expect_false(is.null(nc))
  expect_true(is.finite(nc$blend))
  expect_true(is.finite(nc$labour))
  expect_true(is.finite(nc$expenditure))
  expect_true(nc$w_labour >= 0 && nc$w_labour <= 1)
  expect_equal(nrow(nc$exp_detail$components), length(COMPONENTS))
})

test_that("release detection finds new observations and revisions", {
  v1 <- make_synthetic_vintage()
  v2 <- advance_vintage(v1, c("hours", "mhsi"))
  rel <- detect_releases(v2, v1)
  expect_setequal(rel$key, c("hours", "mhsi"))
  expect_true(all(rel$kind == "new_data"))
  # revision: change an existing value
  v3 <- v2
  v3$data$trade$value[100] <- v3$data$trade$value[100] * 1.05
  rel3 <- detect_releases(v3, v2)
  expect_equal(rel3$key, "trade")
  expect_equal(rel3$kind, "revision")
  # no change -> nothing detected
  expect_equal(nrow(detect_releases(v2, v2)) %||% 0, 0)
})

test_that("attribution impacts sum exactly to the total estimate change", {
  v1 <- make_synthetic_vintage()
  v2 <- advance_vintage(v1, c("hours", "mhsi", "trade"), bump = 0.02)
  rel <- detect_releases(v2, v1)
  asof <- as.Date("2026-06-10"); tq <- "2026Q2"
  base <- nowcast_quarter(v1$data, tq, asof)
  att <- attribute_releases(v2, v1, rel, tq, asof)
  expect_equal(nrow(att$rows), 3)
  expect_equal(sum(att$rows$impact_pp), att$final$blend - base$blend, tolerance = 1e-3)
  # the chain is internally consistent: each row starts where the last ended
  expect_equal(att$rows$old_estimate[-1], att$rows$new_estimate[-nrow(att$rows)])
  expect_equal(att$rows$old_estimate[1], round(base$blend, 4), tolerance = 1e-3)
  expect_equal(att$rows$new_estimate[nrow(att$rows)], round(att$final$blend, 4), tolerance = 1e-3)
})

test_that("attribution with no previous vintage yields a nowcast and no rows", {
  v <- make_synthetic_vintage()
  att <- attribute_releases(v, NULL, NULL, "2026Q2", as.Date("2026-06-10"))
  expect_null(att$rows)
  expect_true(is.finite(att$final$blend))
})

test_that("a NAB file appearing is detected and attributed like any release", {
  v1 <- make_synthetic_vintage()
  v2 <- v1
  months <- seq(as.Date("2023-01-01"), as.Date("2026-05-01"), by = "month")
  v2$data$nab <- rbind(
    data.frame(series_id = "NAB_CONDITIONS", series = "NAB conditions",
               date = months, value = round(stats::rnorm(length(months), 5, 4), 1)),
    data.frame(series_id = "NAB_CAPUTIL", series = "NAB cap util",
               date = months, value = round(81 + cumsum(stats::rnorm(length(months), 0, .3)), 1)))
  rel <- detect_releases(v2, v1)
  expect_true("nab" %in% rel$key)
  att <- attribute_releases(v2, v1, rel, "2026Q2", as.Date("2026-06-10"))
  expect_true("nab" %in% att$rows$source_key)
  expect_true(is.finite(att$final$blend))
})
