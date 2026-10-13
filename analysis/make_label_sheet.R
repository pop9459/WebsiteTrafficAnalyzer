# Draw a stratified, blind labelling sheet from the anonymised requests (KAP-55).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/make_label_sheet.R
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

per_class <- 50
classes <- c("human", "bot", "scanner", "unknown")

requests <- readRDS("data/processed/requests.rds")

ipv4 <- "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b"
requests$referer <- sub("^[a-z]+://([^/]+).*$", "\\1", requests$referer, ignore.case = TRUE)
requests$path <- gsub(ipv4, "<ip>", requests$path)
requests$referer <- gsub(ipv4, "<ip>", requests$referer)

set.seed(2026)
drawn <- requests |>
  filter(client_class %in% classes) |>
  group_by(client_class) |>
  slice_sample(n = per_class) |>
  ungroup() |>
  slice_sample(prop = 1) |>
  mutate(id = row_number())

dir.create("analysis/labelling", showWarnings = FALSE)

drawn |>
  transmute(id, time, via_cloudflare, method, path, status, bytes, referer, user_agent, label = NA_character_) |>
  readr::write_csv("analysis/labelling/label_sheet.csv")

drawn |>
  select(id, predicted = client_class, probe_family) |>
  readr::write_csv("analysis/labelling/label_key.csv")

cat(sprintf("Wrote %d requests to analysis/labelling/label_sheet.csv\n", nrow(drawn)))
print(count(drawn, client_class))
