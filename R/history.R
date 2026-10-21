# Chunked aggregation of very large Docker json-file logs (KAP-104). The
# results hold counts only: no raw line, path, user agent or IP address.

empty_chunk_tables <- function() {
  day0 <- as.Date(character())
  list(
    by_class = tibble::tibble(day = day0, client_class = character(), requests = numeric(), bytes = numeric()),
    by_status = tibble::tibble(day = day0, status_class = character(), requests = numeric()),
    by_probe = tibble::tibble(day = day0, probe_family = character(), requests = numeric()),
    pairs = tibble::tibble(day = day0, ip_hash = character())
  )
}

counter_names <- c("lines", "json_failed", "stdout", "stderr", "parse_ok", "parse_failed")

# Parse the JSON of each line; returns a list(log, stream) with NA where a line failed.
parse_json_lines <- function(lines) {
  one <- function(x) {
    out <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
    if (is.list(out) && is.character(out$log) && length(out$log) == 1 &&
        is.character(out$stream) && length(out$stream) == 1) {
      c(out$log, out$stream)
    } else {
      c(NA_character_, NA_character_)
    }
  }
  # Fast path: one vectorised call; fall back to line by line if any line is bad.
  fast <- tryCatch(
    jsonlite::fromJSON(paste0("[", paste(lines, collapse = ","), "]")),
    error = function(e) NULL
  )
  if (is.data.frame(fast) && nrow(fast) == length(lines) &&
      all(c("log", "stream") %in% names(fast)) &&
      is.character(fast$log) && is.character(fast$stream) &&
      !anyNA(fast$log) && !anyNA(fast$stream)) {
    return(list(log = fast$log, stream = fast$stream))
  }
  res <- vapply(lines, one, character(2), USE.NAMES = FALSE)
  list(log = res[1, ], stream = res[2, ])
}

#' Aggregate one chunk of a Docker json-file log
#'
#' Building block of the chunked importer `data-raw/import_history.R` (KAP-104)
#' for logs too large to hold in memory. Each line is a Docker json-file
#' record; lines that are not valid JSON are skipped and counted. `stdout`
#' lines are parsed with [parse_access_log()], anonymised with
#' [anonymise_requests()] and classified with [classify_requests()]. Only
#' counts leave this function: no raw line, path, user agent or IP address.
#'
#' Classification is done **per chunk**. Rules that look at one client or
#' user agent over time (bursts, 4xx ratio) can therefore be slightly off for
#' clients whose requests are split across a chunk boundary. Days are taken
#' from the request time in the Apache line, in UTC. A line without a valid
#' Apache timestamp counts as `parse_failed`.
#'
#' @param lines Character vector of raw json-file lines (one chunk).
#' @param salt Secret salt, see [get_salt()].
#' @return A list with the tibbles `by_class` (`day`, `client_class`,
#'   `requests`, `bytes`), `by_status` (`day`, `status_class`, `requests`),
#'   `by_probe` (`day`, `probe_family`, `requests`), `pairs` (distinct `day`
#'   and `ip_hash`, to count clients per day after all chunks) and
#'   `counters` (`lines`, `json_failed`, `stdout`, `stderr`, `parse_ok`,
#'   `parse_failed`, `min_time`, `max_time` of the parsed requests).
#' @seealso [combine_history_chunks()]
#' @export
aggregate_log_chunk <- function(lines, salt) {
  js <- parse_json_lines(lines)
  json_ok <- !is.na(js$log)
  is_out <- json_ok & js$stream == "stdout"
  is_err <- json_ok & js$stream == "stderr"

  access <- sub("\r?\n$", "", js$log[is_out])
  # Silenced: readr's warnings would echo the offending (raw) text.
  parsed <- suppressWarnings(parse_access_log(access))
  # A line that matches the regex but has no valid timestamp (e.g. Flask's
  # "[12/Sep/2025 10:00:44]") is not an access-log line.
  ok <- parsed$parse_ok & !is.na(parsed$time)
  parsed <- parsed[ok, ]

  res <- empty_chunk_tables()
  min_time <- max_time <- NA_real_
  if (nrow(parsed) > 0) {
    req <- parsed |>
      anonymise_requests(salt) |>
      classify_requests()
    req$day <- as.Date(req$time, tz = "UTC")
    res$by_class <- req |>
      dplyr::summarise(requests = dplyr::n(), bytes = sum(.data$bytes, na.rm = TRUE),
                       .by = c("day", "client_class"))
    res$by_status <- req |>
      dplyr::mutate(status_class = paste0(.data$status %/% 100, "xx")) |>
      dplyr::summarise(requests = dplyr::n(), .by = c("day", "status_class"))
    res$by_probe <- req |>
      dplyr::summarise(requests = dplyr::n(), .by = c("day", "probe_family"))
    res$pairs <- dplyr::distinct(req[, c("day", "ip_hash")])
    min_time <- min(as.numeric(req$time), na.rm = TRUE)
    max_time <- max(as.numeric(req$time), na.rm = TRUE)
  }

  res$counters <- list(
    lines = length(lines),
    json_failed = sum(!json_ok),
    stdout = sum(is_out),
    stderr = sum(is_err),
    parse_ok = sum(ok),
    parse_failed = sum(!ok),
    min_time = as.POSIXct(min_time, origin = "1970-01-01", tz = "UTC"),
    max_time = as.POSIXct(max_time, origin = "1970-01-01", tz = "UTC")
  )
  res
}

#' Combine the results of [aggregate_log_chunk()]
#'
#' Sums the counts, takes the overall first and last request time and turns
#' the distinct (day, client) pairs into a per-day client count. A client seen
#' in several chunks on the same day is counted once.
#'
#' Results of this function can be passed in again, so a long file can be
#' folded chunk by chunk (use `keep_pairs = TRUE` for the intermediate
#' results).
#'
#' @param chunks List of results of [aggregate_log_chunk()] or of earlier
#'   calls to this function made with `keep_pairs = TRUE`.
#' @param keep_pairs If `TRUE`, keep the (day, `ip_hash`) pairs in the result
#'   (for further combining). The default drops them: only the per-day client
#'   counts remain, so nothing client-level is stored.
#' @return A list like [aggregate_log_chunk()], plus `clients` (`day`,
#'   `clients`); `pairs` is `NULL` unless `keep_pairs = TRUE`.
#' @export
combine_history_chunks <- function(chunks, keep_pairs = FALSE) {
  bind <- function(name) dplyr::bind_rows(lapply(chunks, `[[`, name))
  sum_by <- function(x, keys, values) {
    x |>
      dplyr::summarise(dplyr::across(dplyr::all_of(values), sum), .by = dplyr::all_of(keys)) |>
      dplyr::arrange(dplyr::across(dplyr::all_of(keys)))
  }
  pairs <- dplyr::distinct(bind("pairs"))

  counters <- lapply(counter_names, function(n) sum(vapply(chunks, function(x) x$counters[[n]], numeric(1))))
  names(counters) <- counter_names
  times <- function(n) {
    v <- vapply(chunks, function(x) as.numeric(x$counters[[n]]), numeric(1))
    v <- v[!is.na(v)]
    as.POSIXct(if (length(v)) v else NA_real_, origin = "1970-01-01", tz = "UTC")
  }
  counters$min_time <- min(times("min_time"))
  counters$max_time <- max(times("max_time"))

  list(
    by_class = sum_by(bind("by_class"), c("day", "client_class"), c("requests", "bytes")),
    by_status = sum_by(bind("by_status"), c("day", "status_class"), "requests"),
    by_probe = sum_by(bind("by_probe"), c("day", "probe_family"), "requests"),
    clients = pairs |>
      dplyr::summarise(clients = dplyr::n(), .by = "day") |>
      dplyr::arrange(.data$day),
    pairs = if (keep_pairs) pairs else NULL,
    counters = counters
  )
}
