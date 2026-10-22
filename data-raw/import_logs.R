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
# Default: the regular files directly in data/raw/. To include the persisted
# server logs from scripts/fetch_logs.sh, pass them as arguments too, e.g.
#   Rscript data-raw/import_logs.R data/raw/*.gz data/raw/vps/access.log* data/raw/vps/error.log*
default_files <- list.files("data/raw", full.names = TRUE)
files <- if (length(args)) args else default_files[!dir.exists(default_files)]
if (!length(files)) stop("No raw log files found in data/raw/.")

# Plain Apache error logs (data/raw/vps/error.log*) have no stream marker, so
# their lines are treated as the stderr stream, like Docker's json-file log.
read_one <- function(path) {
  out <- read_raw_log(path)
  if (grepl("^error\\.log", basename(path))) out$stream <- "stderr"
  out
}
raw <- dplyr::bind_rows(lapply(files, read_one))
salt <- get_salt(create = TRUE)

access <- raw[raw$stream %in% "stdout", ]
errors <- raw[raw$stream %in% "stderr", c("time", "line")]
# Plain error.log files carry no Docker receive time: take it from the line.
no_time <- is.na(errors$time)
errors$time[no_time] <- parse_error_log(errors$line[no_time])$time

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
# Geo: no organisation names, and country/ASN only where the pair is common
# enough in the sample (>= 5 requests) not to single out a home connection.
sample_rows$as_org <- NULL
pair_n <- ave(seq_len(nrow(sample_rows)), sample_rows$country, sample_rows$asn, FUN = length)
rare <- is.na(sample_rows$country) | is.na(sample_rows$asn) | pair_n < 5
sample_rows$country[rare] <- NA
sample_rows$asn[rare] <- NA
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
cat(sprintf("Geo resolved:       %.1f%% of direct-to-origin requests\n",
            100 * mean(!is.na(requests$country[requests$via_cloudflare %in% FALSE]))))
cat("Client classes:\n")
print(dplyr::count(requests, client_class, sort = TRUE) |> dplyr::mutate(share = round(n / sum(n), 3)))
