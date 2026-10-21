# Write the dashboard aggregates as JSON (KAP-56).
#
# Usage (from the repo root):
#   Rscript data-raw/export_dashboard.R           # full data, after import_logs.R
#   Rscript data-raw/export_dashboard.R --sample  # committed sample only
#
# Writes
#   data/processed/dashboard.json      from data/processed/requests.rds (git-ignored)
#   data/sample/dashboard_sample.json  from data/sample/requests_sample.csv (safe to commit)

devtools::load_all(quiet = TRUE)

if ("--sample" %in% commandArgs(trailingOnly = TRUE)) {
  requests <- readr::read_csv("data/sample/requests_sample.csv", show_col_types = FALSE)
  out <- "data/sample/dashboard_sample.json"
} else {
  requests <- readRDS("data/processed/requests.rds")
  out <- "data/processed/dashboard.json"
}

export_dashboard_json(requests, out)
cat(sprintf("Wrote %s: %d requests, %s to %s\n", out, nrow(requests),
            format(min(requests$time)), format(max(requests$time))))
