#' Read a raw web-server log export
#'
#' Reads one log file and returns one row per log line. Three formats are
#' detected from the first non-empty line:
#'
#' * **json**: Docker's `json-file` log driver, one JSON object per line with
#'   `log`, `stream` and `time` (e.g. a copy of
#'   `/var/lib/docker/containers/<id>/<id>-json.log`).
#' * **timestamped**: output of `docker logs --timestamps`, every line prefixed
#'   with an RFC 3339 timestamp. stdout and stderr are merged, so `stream` is
#'   `NA`.
#' * **plain**: a plain Apache access log file. `time` is `NA` (the request
#'   time comes from the parsed line) and `stream` is `"stdout"`.
#'
#' Gzipped files are read transparently.
#'
#' @param path Path to the log file.
#' @return A tibble with columns `time` (POSIXct, UTC, time Docker received
#'   the line), `stream` (`"stdout"`/`"stderr"`) and `line` (the raw log line).
#' @export
read_raw_log <- function(path) {
  lines <- readr::read_lines(path, progress = FALSE)
  lines <- lines[nzchar(lines)]

  if (length(lines) == 0) {
    return(tibble::tibble(
      time = as.POSIXct(character(), tz = "UTC"),
      stream = character(),
      line = character()
    ))
  }

  switch(detect_log_format(lines[[1]]),
    json = {
      parsed <- jsonlite::fromJSON(paste0("[", paste(lines, collapse = ","), "]"))
      tibble::tibble(
        time = parse_docker_time(parsed$time),
        stream = parsed$stream,
        line = sub("\r?\n$", "", parsed$log)
      )
    },
    timestamped = tibble::tibble(
      time = parse_docker_time(sub(" .*$", "", lines)),
      stream = NA_character_,
      line = sub("^\\S+ ", "", lines)
    ),
    plain = tibble::tibble(
      time = as.POSIXct(rep(NA_real_, length(lines)), tz = "UTC"),
      stream = "stdout",
      line = lines
    )
  )
}

#' Detect which raw log format a line is in
#'
#' @param line A single log line.
#' @return One of `"json"`, `"timestamped"` or `"plain"`.
#' @keywords internal
detect_log_format <- function(line) {
  if (startsWith(line, "{")) {
    "json"
  } else if (grepl("^\\d{4}-\\d{2}-\\d{2}T\\S+Z ", line)) {
    "timestamped"
  } else {
    "plain"
  }
}

#' Parse Docker's RFC 3339 timestamps (with nanoseconds) as UTC
#'
#' @param x Character vector such as `"2026-07-09T21:43:32.269408593Z"`.
#' @return POSIXct in UTC.
#' @keywords internal
parse_docker_time <- function(x) {
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
}
