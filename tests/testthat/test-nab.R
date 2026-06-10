make_nab_csv <- function(dir, months = 18, fname = "nab_survey.csv",
                         end = as.Date("2026-05-01")) {
  dates <- seq(end, by = "-1 month", length.out = months)
  df <- data.frame(
    Month = format(rev(dates), "%b %Y"),
    `Business confidence` = round(stats::rnorm(months, 3, 5), 1),
    `Business conditions` = round(stats::rnorm(months, 6, 5), 1),
    `Trading conditions` = round(stats::rnorm(months, 9, 5), 1),
    `Capacity utilisation` = round(82 + cumsum(stats::rnorm(months, 0, .4)), 1),
    Employment = round(stats::rnorm(months, 2, 4), 1),
    check.names = FALSE)
  utils::write.csv(df, file.path(dir, fname), row.names = FALSE)
  invisible(df)
}

test_that("empty NAB folder yields empty data and an 'awaiting' status", {
  dir <- file.path(tempdir(), paste0("nab-empty-", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(dir)
  got <- read_nab_folder(dir)
  expect_equal(nrow(got), 0)
  st <- nab_status(got, as.Date("2026-06-10"))
  expect_false(st$available)
  expect_match(st$message, "awaiting")
})

test_that("a NAB file is parsed by header matching", {
  dir <- file.path(tempdir(), paste0("nab-ok-", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(dir)
  make_nab_csv(dir)
  got <- read_nab_folder(dir)
  expect_true(all(c("NAB_CONDITIONS", "NAB_CONFIDENCE", "NAB_CAPUTIL") %in% got$series_id))
  expect_equal(max(got$date), as.Date("2026-05-01"))
  st <- nab_status(got, as.Date("2026-06-10"))
  expect_true(st$available)
  expect_match(st$message, "received for May 2026")
})

test_that("a stale NAB file flips the status to awaiting without failing", {
  dir <- file.path(tempdir(), paste0("nab-stale-", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(dir)
  make_nab_csv(dir, end = as.Date("2026-02-01"))
  got <- read_nab_folder(dir)
  expect_gt(nrow(got), 0)
  st <- nab_status(got, as.Date("2026-06-10"))
  expect_false(st$available)
  expect_match(st$message, "awaiting")
})

test_that("a malformed NAB file is skipped without error", {
  dir <- file.path(tempdir(), paste0("nab-bad-", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(dir)
  writeLines(c("this,is,not", "a,survey,file", "1,2,3"), file.path(dir, "junk.csv"))
  expect_silent({ got <- read_nab_folder(dir) })
  expect_equal(nrow(got), 0)
})

test_that("a newer NAB file overrides overlapping months from an older one", {
  dir <- file.path(tempdir(), paste0("nab-two-", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(dir)
  make_nab_csv(dir, fname = "old.csv", end = as.Date("2026-04-01"))
  Sys.sleep(1.1)  # ensure distinct mtimes
  df <- make_nab_csv(dir, fname = "new.csv", end = as.Date("2026-05-01"))
  got <- read_nab_folder(dir)
  expect_equal(max(got$date), as.Date("2026-05-01"))
  may_cond <- got$value[got$series_id == "NAB_CONDITIONS" & got$date == as.Date("2026-05-01")]
  expect_equal(may_cond, df$`Business conditions`[nrow(df)])
})
