# Import raw log exports into anonymised, classified tables.
#
# Usage (from the repo root):
#   Rscript data-raw/import_logs.R [raw log files...]
# Without arguments every file in data/raw/ is imported.
#
# Writes
#   data/processed/requests.rds  all access-log requests (git-ignored)
#   data/processed/errors.rds    the stderr (error log) lines (git-ignored)
#   data/sample/requests_sample.csv  2,000 random requests, safe to commit

devtools::load_all(quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
# Default: the regular files directly in data/raw/. The folder data/raw/vps/
# (scripts/fetch_logs.sh) is used by analysis/fix_effect.R; pass its files as
# arguments to import them here.
default_files <- list.files("data/raw", full.names = TRUE)
files <- if (length(args)) args else default_files[!dir.exists(default_files)]
if (!length(files)) stop("No raw log files found in data/raw/.")

raw <- dplyr::bind_rows(lapply(files, read_raw_log))
salt <- get_salt(create = TRUE)

access <- raw[raw$stream %in% "stdout", ]
errors <- raw[raw$stream %in% "stderr", c("time", "line")]

parsed <- parse_access_log(access$line)
parsed$received <- access$time

requests <- parsed[parsed$parse_ok, ] |>
  anonymise_requests(salt) |>
  classify_requests()

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("data/sample", recursive = TRUE, showWarnings = FALSE)
saveRDS(requests, "data/processed/requests.rds")
saveRDS(errors, "data/processed/errors.rds")

# Committed sample: no query strings or full referers, which can carry
# personal data; the referer is cut down to its host, and IP addresses left
# in paths and referers (proxy probes, the server's own address) are masked.
set.seed(42)
sample_rows <- requests[sort(sample.int(nrow(requests), min(2000, nrow(requests)))), ]
sample_rows$query <- NULL
sample_rows$request <- NULL
sample_rows$referer <- sub("^[a-z]+://([^/]+).*$", "\\1", sample_rows$referer, ignore.case = TRUE)
ipv4 <- "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b"
sample_rows$path <- gsub(ipv4, "<ip>", sample_rows$path)
sample_rows$referer <- gsub(ipv4, "<ip>", sample_rows$referer)
readr::write_csv(sample_rows, "data/sample/requests_sample.csv")

cat(sprintf("Raw lines:          %d (%d stdout, %d stderr)\n", nrow(raw), nrow(access), nrow(errors)))
cat(sprintf("Unparsed lines:     %d\n", sum(!parsed$parse_ok)))
cat(sprintf("Requests:           %d from %s to %s\n", nrow(requests),
            format(min(requests$time)), format(max(requests$time))))
cat(sprintf("Via Cloudflare:     %.1f%%\n", 100 * mean(requests$via_cloudflare, na.rm = TRUE)))
cat("Client classes:\n")
print(dplyr::count(requests, client_class, sort = TRUE) |> dplyr::mutate(share = round(n / sum(n), 3)))
