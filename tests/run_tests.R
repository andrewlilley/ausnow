#!/usr/bin/env Rscript
# Test runner: source the R/ modules into the global env, then run testthat.
setwd(Sys.getenv("AUSNOW_ROOT", "."))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
library(testthat)
res <- test_dir("tests/testthat", stop_on_failure = TRUE)
