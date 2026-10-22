# KAP-60: logs -> parse -> anonymise -> classify -> aggregate -> JSON.
# Runs inside the container (see deploy/Dockerfile). Prints aggregates only.
# Configuration comes from environment variables set by run_pipeline.sh:
#   WTA_LOG_DIR, WTA_TMP_FILE, WTA_SALT, optional WTA_GEO_DIR.

suppressPackageStartupMessages(library(trafficanalyzer))
t0 <- Sys.time()

log_dir  <- Sys.getenv("WTA_LOG_DIR", "/logs")
tmp_file <- Sys.getenv("WTA_TMP_FILE", "/out/traffic.json.tmp")
salt     <- get_salt()

# Only the main access logs: access.log, access.log.1, access.log.2.gz, ...
# (not error.log* and not other_vhosts_access.log).
files <- list.files(log_dir, pattern = "^access\\.log(\\.[0-9]+)?(\\.gz)?$", full.names = TRUE)
if (!length(files)) stop("no access.log* files in ", log_dir)

raw <- dplyr::bind_rows(lapply(files, read_raw_log))
access <- raw[raw$stream %in% "stdout", ]
if (!nrow(access)) stop("no access-log lines found in ", length(files), " files")
rm(raw)

parsed <- parse_access_log(access$line)
parsed$received <- access$time
n_lines <- nrow(access)
rm(access)

requests <- parsed[parsed$parse_ok, ]
n_unparsed <- sum(!parsed$parse_ok)
rm(parsed)
if (!nrow(requests)) stop("none of ", n_lines, " lines could be parsed")

requests <- requests |>
  anonymise_requests(salt) |>
  classify_requests()

export_dashboard_json(requests, tmp_file)

# Aggregate report (no log lines, no addresses).
cat(sprintf("files=%d lines=%d unparsed=%d requests=%d\n",
            length(files), n_lines, n_unparsed, nrow(requests)))
cat(sprintf("range=%s..%s\n", format(min(requests$time), "%Y-%m-%d"),
            format(max(requests$time), "%Y-%m-%d")))
cls <- table(requests$client_class)
cat("classes: ", paste(names(cls), as.integer(cls), sep = "=", collapse = " "), "\n", sep = "")
cat(sprintf("geo_resolved_direct=%.1f%%\n",
            100 * mean(!is.na(requests$country[requests$via_cloudflare %in% FALSE]))))
mem <- gc()
cat(sprintf("elapsed_s=%.1f r_peak_mem_mb=%.0f\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")), sum(mem[, ncol(mem)])))
peak <- "/sys/fs/cgroup/memory.peak"
if (file.exists(peak)) {
  cat(sprintf("cgroup_peak_mem_mb=%.0f\n", as.numeric(readLines(peak, n = 1)) / 1024^2))
}
