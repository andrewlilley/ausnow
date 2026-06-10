test_that("quarter helpers are correct across year boundaries", {
  expect_equal(quarter_label(as.Date("2026-01-15")), "2026Q1")
  expect_equal(quarter_label(as.Date("2025-12-31")), "2025Q4")
  expect_equal(shift_quarter("2025Q4", 1), "2026Q1")
  expect_equal(shift_quarter("2026Q1", -1), "2025Q4")
  expect_equal(shift_quarter("2024Q2", 7), "2026Q1")
  expect_equal(quarter_start("2026Q3"), as.Date("2026-07-01"))
  expect_equal(quarter_end("2025Q4"), as.Date("2025-12-31"))
  expect_equal(quarter_diff("2026Q1", "2025Q3"), 2)
})

test_that("GDP release dates follow the first-Wednesday rule", {
  # 2026Q1 GDP: first Wednesday of June 2026 = 3 June
  expect_equal(gdp_release_date("2026Q1"), as.Date("2026-06-03"))
  # 2025Q4 GDP: first Wednesday of March 2026 = 4 March
  expect_equal(gdp_release_date("2025Q4"), as.Date("2026-03-04"))
  # year boundary: 2025Q3 -> first Wednesday of December 2025 = 3 December
  expect_equal(gdp_release_date("2025Q3"), as.Date("2025-12-03"))
})

test_that("live targets roll over correctly, including year boundaries", {
  # Right after Q1 publication in June: only Q2 is live
  expect_equal(live_targets("2026Q1", as.Date("2026-06-10")), "2026Q2")
  # Before Q1 publication in May: Q1 (completed) and Q2 (current)
  expect_equal(live_targets("2025Q4", as.Date("2026-05-10")), c("2026Q1", "2026Q2"))
  # December before Q3 GDP lands: Q3 completed-unreleased + Q4 current
  expect_equal(live_targets("2025Q2", as.Date("2025-11-30")), c("2025Q3", "2025Q4"))
  # New year flip: published through Q3, today early January
  expect_equal(live_targets("2025Q3", as.Date("2026-01-05")), c("2025Q4", "2026Q1"))
  # degenerate: GDP published for the current quarter (cannot happen live)
  expect_equal(live_targets("2026Q2", as.Date("2026-06-10")), character(0))
})

test_that("target status distinguishes completed from current", {
  expect_equal(target_status("2026Q1", as.Date("2026-05-10")), "completed-unreleased")
  expect_equal(target_status("2026Q2", as.Date("2026-05-10")), "current")
})

test_that("quarter rollover: GDP print retires the quarter and promotes the next", {
  # walk a full publication cycle with the state machine
  today1 <- as.Date("2026-06-02")   # day before Q1 release
  expect_equal(live_targets("2025Q4", today1), c("2026Q1", "2026Q2"))
  today2 <- as.Date("2026-06-03")   # Q1 GDP published at 11:30
  expect_equal(live_targets("2026Q1", today2), "2026Q2")
  today3 <- as.Date("2026-07-01")   # Q2 ends, Q3 opens
  expect_equal(live_targets("2026Q1", today3), c("2026Q2", "2026Q3"))
  expect_equal(target_status("2026Q2", today3), "completed-unreleased")
})
