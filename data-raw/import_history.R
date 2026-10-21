# Chunked, memory-safe importer for the large historical Docker json-file logs
# (KAP-104). Meant for the LOCAL-ONLY backup; it prints and stores aggregates
# only (counts per day, class, status, probe family; never a raw line, path,
# user agent or IP address).
#
# Usage (from the repo root):
#   Rscript data-raw/import_history.R [--out DIR] [--chunk N] FILE...
# Defaults: --out data/processed/history, --chunk 200000 lines.
#
# Writes
#   <out>/<file basename>.rds  combined aggregates of that file (per-day client
#                              counts, no per-client hashes)
#   <out>/history_daily.csv    file, day, client_class, requests, bytes
#
# Classification is done per chunk, so per-client rules (bursts, 404 ratio) can
# be slightly off at chunk boundaries.

devtools::load_all(quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
out_dir <- "data/processed/history"
chunk_size <- 200000L
files <- character()
i <- 1
while (i <= length(args)) {
  if (args[i] == "--out") {
    out_dir <- args[i + 1]; i <- i + 2
  } else if (args[i] == "--chunk") {
    chunk_size <- as.integer(args[i + 1]); i <- i + 2
  } else {
    files <- c(files, args[i]); i <- i + 1
  }
}
if (!length(files)) stop("Usage: Rscript data-raw/import_history.R [--out DIR] [--chunk N] FILE...")
if (is.na(chunk_size) || chunk_size < 1) stop("--chunk must be a positive integer.")
missing_files <- files[!file.exists(files)]
if (length(missing_files)) stop(length(missing_files), " input file(s) not found.")

salt <- tryCatch(
  get_salt(create = FALSE),
  error = function(e) stop("No salt found: set WTA_SALT or create ~/.config/websitetrafficanalyzer/salt.", call. = FALSE)
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

daily <- list()
for (file in files) {
  name <- basename(file)
  started <- Sys.time()
  acc <- NULL
  readr::read_lines_chunked(
    file,
    readr::SideEffectChunkCallback$new(function(lines, pos) {
      res <- aggregate_log_chunk(lines, salt)
      acc <<- combine_history_chunks(if (is.null(acc)) list(res) else list(acc, res), keep_pairs = TRUE)
    }),
    chunk_size = chunk_size,
    progress = FALSE
  )
  if (is.null(acc)) {
    cat(sprintf("%s: empty file\n", name))
    next
  }
  result <- combine_history_chunks(list(acc), keep_pairs = FALSE)
  rm(acc)
  saveRDS(result, file.path(out_dir, paste0(sub("\\.gz$", "", name), ".rds")))

  cn <- result$counters
  share <- if (cn$stdout > 0) cn$parse_ok / cn$stdout else 0
  role <- if (share >= 0.5) "web" else "other"
  per_class <- tapply(result$by_class$requests, result$by_class$client_class, sum)
  cat(sprintf("== %s\n", name))
  cat(sprintf("lines %s | json_failed %s | stdout %s | stderr %s | parse_ok %.1f%% of stdout\n",
              format(cn$lines, big.mark = ","), format(cn$json_failed, big.mark = ","),
              format(cn$stdout, big.mark = ","), format(cn$stderr, big.mark = ","), 100 * share))
  cat(sprintf("first day %s | last day %s | days covered %d\n",
              format(cn$min_time, "%Y-%m-%d"), format(cn$max_time, "%Y-%m-%d"),
              length(unique(result$by_class$day))))
  cat("requests per class: ",
      if (length(per_class)) paste0(names(per_class), "=", format(as.numeric(per_class), big.mark = ","), collapse = ", ") else "none",
      "\n", sep = "")
  cat(sprintf("role guess: %s | elapsed %.1f s\n",
              role, as.numeric(difftime(Sys.time(), started, units = "secs"))))

  if (nrow(result$by_class) > 0) {
    daily[[name]] <- cbind(file = name, as.data.frame(result$by_class))
  }
  rm(result)
  gc()
}

all_daily <- do.call(rbind, daily)
if (!is.null(all_daily)) {
  utils::write.csv(all_daily, file.path(out_dir, "history_daily.csv"), row.names = FALSE)
}
g <- gc()
cat(sprintf("peak R memory (gc max used): %.0f MB\n", sum(g[, 6])))
