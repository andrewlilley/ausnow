#!/usr/bin/env Rscript
# AusNow daily pipeline entry point. The logic lives in R/pipeline.R.
setwd(Sys.getenv("AUSNOW_ROOT", "."))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
run_pipeline()
