# Draw a stratified, blind labelling sheet from the anonymised requests (KAP-55).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/make_label_sheet.R        # development sheet, analysis/labelling/
#   Rscript analysis/make_label_sheet.R test   # fresh test sheet, analysis/labelling/test/
#
# The test sheet uses another seed and leaves out every request of the
# development sheet. Tune the classifier on the development sheet only and
# report the accuracy measured on the test sheet.
#
# Draws from data/processed/requests.rds (the committed sample has too few
# human requests). Paths and referers are masked like in the committed sample,
# so the sheet itself can be committed.
#
# Writes to analysis/labelling/
#   label_sheet.csv  what you label: the request without its predicted class
#   label_key.csv    the classifier's answer per id; do not open before labelling
# Fill the `label` column of label_sheet.csv with one of:
#   human, bot, scanner, unknown (cannot tell)
# then run analysis/label_accuracy.R.

suppressPackageStartupMessages(library(dplyr))

mode <- if (length(commandArgs(trailingOnly = TRUE))) commandArgs(trailingOnly = TRUE)[[1]] else "dev"
stopifnot(mode %in% c("dev", "test"))
out_dir <- if (mode == "test") "analysis/labelling/test" else "analysis/labelling"
per_class <- 50
classes <- c("human", "bot", "scanner", "unknown")

requests <- readRDS("data/processed/requests.rds")

ipv4 <- "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b"
requests$referer <- sub("^[a-z]+://([^/]+).*$", "\\1", requests$referer, ignore.case = TRUE)
requests$path <- gsub(ipv4, "<ip>", requests$path)
requests$referer <- gsub(ipv4, "<ip>", requests$referer)

if (mode == "test") {
  dev <- readr::read_csv("analysis/labelling/label_sheet.csv", show_col_types = FALSE)
  dev_id <- paste(format(dev$time, "%Y-%m-%dT%H:%M:%SZ"), dev$path, dev$user_agent)
  seen <- paste(format(requests$time, "%Y-%m-%dT%H:%M:%SZ"), requests$path, requests$user_agent) %in% dev_id
  requests <- requests[!seen, ]
}

set.seed(if (mode == "test") 2027 else 2026)
drawn <- requests |>
  filter(client_class %in% classes) |>
  group_by(client_class) |>
  slice_sample(n = per_class) |>
  ungroup() |>
  slice_sample(prop = 1) |>
  mutate(id = row_number())

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

drawn |>
  transmute(id, time, via_cloudflare, method, path, status, bytes, referer, user_agent, label = NA_character_) |>
  readr::write_csv(file.path(out_dir, "label_sheet.csv"))

drawn |>
  select(id, predicted = client_class, probe_family) |>
  readr::write_csv(file.path(out_dir, "label_key.csv"))

cat(sprintf("Wrote %d requests to %s\n", nrow(drawn), file.path(out_dir, "label_sheet.csv")))
print(count(drawn, client_class))
