# Apache "combined" log line, with the optional "%I %O %D" suffix (bytes
# received, bytes sent, response time in microseconds) and, after it, the
# optional "%{c}a" connection address that the extended format of KAP-49 adds.
# Quoted fields allow backslash escapes.
quoted <- '"((?:[^"\\\\]|\\\\.)*)"'
combined_regex <- paste0(
  "^(\\S+) (\\S+) (\\S+) \\[([^\\]]+)\\] ", quoted, " (\\d{3}) (\\S+)",
  "(?: ", quoted, " ", quoted, ")?",
  "(?: (\\d+) (\\d+) (\\d+)(?: (\\S+))?)?$"
)

#' Parse Apache access-log lines
#'
#' Parses lines in Apache `combined` format, with or without the trailing
#' `%I %O %D` fields and the connection address `%{c}a` after them. Lines that
#' do not match keep their row with `parse_ok = FALSE`, so data-quality checks
#' can count them.
#'
#' With the extended log format, `ip` is the visitor address (after
#' `mod_remoteip`) and `peer_ip` is the address that actually connected, which
#' is a Cloudflare edge address for proxied requests. `peer_ip` is `NA` for
#' older lines, where `ip` is already the connecting address.
#'
#' A `-` response size means no body was sent and becomes `0`. The request
#' line is split into method, path, query and protocol; a malformed request
#' line (e.g. a TLS handshake sent to the HTTP port) leaves those fields `NA`.
#'
#' @param lines Character vector of access-log lines.
#' @return A tibble with one row per line: `ip`, `ident`, `user`, `time`
#'   (request time, POSIXct UTC), `request`, `method`, `path`, `query`,
#'   `protocol`, `status`, `bytes`, `referer`, `user_agent`, `bytes_in`,
#'   `bytes_out`, `duration_us`, `peer_ip` and `parse_ok`.
#' @export
parse_access_log <- function(lines) {
  m <- stringr::str_match(lines, combined_regex)
  parse_ok <- !is.na(m[, 1])

  request <- unescape_apache(m[, 6])
  req <- stringr::str_match(request, "^([A-Za-z]+) (\\S+)(?: (HTTP/[0-9.]+))?$")
  target <- req[, 3]

  tibble::tibble(
    ip = m[, 2],
    ident = m[, 3],
    user = m[, 4],
    time = readr::parse_datetime(m[, 5], format = "%d/%b/%Y:%H:%M:%S %z"),
    request = request,
    method = req[, 2],
    path = sub("\\?.*$", "", target),
    query = ifelse(grepl("?", target, fixed = TRUE), sub("^[^?]*\\?", "", target), NA_character_),
    protocol = req[, 4],
    status = as.integer(m[, 7]),
    bytes = ifelse(m[, 8] == "-", 0, suppressWarnings(as.numeric(m[, 8]))),
    referer = dash_to_na(unescape_apache(m[, 9])),
    user_agent = dash_to_na(unescape_apache(m[, 10])),
    bytes_in = as.numeric(m[, 11]),
    bytes_out = as.numeric(m[, 12]),
    duration_us = as.numeric(m[, 13]),
    peer_ip = m[, 14],
    parse_ok = parse_ok
  )
}

#' Undo Apache's escaping of quotes and backslashes in quoted fields
#' @keywords internal
unescape_apache <- function(x) {
  x <- gsub('\\"', '"', x, fixed = TRUE)
  gsub("\\\\", "\\", x, fixed = TRUE)
}

#' Turn Apache's `-` placeholder into `NA`
#' @keywords internal
dash_to_na <- function(x) {
  ifelse(x == "-", NA_character_, x)
}
