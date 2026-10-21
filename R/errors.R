#' Parse Apache/PHP error-log lines
#'
#' Parses lines from the Apache error log (stderr of the `php:8.2-apache`
#' container), e.g.
#' `[Tue Oct 07 10:28:01.123456 2026] [php:warn] [pid 23] [client 203.0.113.5:4711] PHP Warning:  ...`.
#' Lines that are not bracketed but start with an `AH#####` code (such as the
#' ServerName notice at start-up) are parsed without time, module and level.
#' All other lines are kept with `parse_ok = FALSE`.
#'
#' The client address (`[client ip:port]`) is dropped and any other IPv4
#' address inside the message is masked, so the result contains no
#' identifiable data. `message_template` normalises the message so that similar
#' errors group together: the Apache code and the PHP error type are removed
#' (they have their own columns), `referer:` suffixes are removed, request
#' targets and other paths become `<path>`, quoted strings become `<s>`,
#' IPv4 addresses become `<ip>` and numbers become `<n>`. The file path after
#' `in /` is kept (without line number) because it points at the code that
#' raised the error.
#'
#' @param lines Character vector of raw error-log lines.
#'
#' @return A tibble with one row per input line and columns `time` (POSIXct,
#'   UTC, `NA` if the line has no timestamp), `module`, `level`, `ah_code`
#'   (e.g. `"AH00126"` or `NA`), `php_error_type` (`"Warning"`, `"Notice"`,
#'   `"Fatal error"`, `"Deprecated"`, ... or `NA`), `message_template` and
#'   `parse_ok` (logical).
#' @export
#' @examples
#' parse_error_log(c(
#'   paste0(
#'     "[Tue Oct 07 10:28:01.123456 2026] [core:error] [pid 23] ",
#'     "[client 203.0.113.5:4711] AH00126: Invalid URI in request GET /%%% HTTP/1.1"
#'   ),
#'   "not an error line"
#' ))
parse_error_log <- function(lines) {
  lines <- as.character(lines)
  n <- length(lines)
  lines[is.na(lines)] <- ""

  bracket_re <- paste0(
    "^\\[([A-Z][a-z]{2}) ([A-Z][a-z]{2}) (\\d{1,2}) (\\d{2}:\\d{2}:\\d{2})(?:\\.\\d+)? (\\d{4})\\]",
    "\\s+\\[([A-Za-z0-9_]+):([a-z0-9]+)\\]",
    "(?:\\s+\\[pid [^\\]]*\\])?(?:\\s+\\[tid [^\\]]*\\])?(?:\\s+\\[client [^\\]]*\\])?\\s*(.*)$"
  )
  m <- stringr::str_match(lines, bracket_re)
  bracketed <- !is.na(m[, 1])

  month <- match(m[, 3], month.abb)
  time <- as.POSIXct(
    ifelse(bracketed & !is.na(month),
      sprintf("%s-%02d-%02d %s", m[, 6], month, as.integer(m[, 4]), m[, 5]), NA_character_
    ),
    tz = "UTC", format = "%Y-%m-%d %H:%M:%S"
  )

  # Message part: after the bracket prefix, or the whole line when it starts
  # with an Apache code or a PHP error prefix.
  bare_ok <- !bracketed & stringr::str_detect(lines, "^(AH\\d{5}:|PHP [A-Z])")
  msg <- ifelse(bracketed, m[, 9], ifelse(bare_ok, lines, ""))
  msg[is.na(msg)] <- ""
  parse_ok <- bracketed | bare_ok

  msg <- stringr::str_remove(msg, ",\\s*referer: .*$")

  ah_code <- stringr::str_match(msg, "^(AH\\d{5}):")[, 2]
  msg <- stringr::str_remove(msg, "^AH\\d{5}:\\s*")

  type_re <- "^PHP (Warning|Notice|Fatal error|Deprecated|Parse error|Strict Standards|Error):\\s+"
  php_error_type <- stringr::str_match(msg, type_re)[, 2]
  msg <- stringr::str_remove(msg, type_re)

  # Keep the file path after " in /", drop the line number.
  file_re <- "\\sin (/[^\\s:,]+)(?::\\d+|\\s+on line \\d+)?"
  file_path <- stringr::str_match(msg, file_re)[, 2]
  msg <- stringr::str_replace(msg, file_re, " in \001")

  methods <- "(GET|POST|HEAD|PUT|DELETE|OPTIONS|PATCH|CONNECT|TRACE|PROPFIND)"
  msg <- stringr::str_replace_all(msg, paste0("\\b", methods, "\\s+\\S+(\\s+HTTP/)"), "\\1 <path>\\2")
  msg <- stringr::str_replace_all(msg, "(?<![A-Za-z0-9])'[^']*'", "<s>")
  msg <- stringr::str_replace_all(msg, "\"[^\"]*\"", "<s>")
  msg <- stringr::str_replace_all(msg, "(?<![\\w<>/])/[^\\s,;:()\u0001]*", "<path>")
  msg <- stringr::str_replace_all(msg, "\\b(\\d{1,3}\\.){3}\\d{1,3}\\b", "<ip>")
  msg <- stringr::str_replace_all(msg, "\\d+", "<n>")
  msg <- stringr::str_squish(msg)
  has_file <- !is.na(file_path)
  msg[has_file] <- stringr::str_replace(msg[has_file], "\001", file_path[has_file])
  msg[!parse_ok] <- NA_character_

  tibble::tibble(
    time = time,
    module = ifelse(bracketed, m[, 7], NA_character_),
    level = ifelse(bracketed, m[, 8], NA_character_),
    ah_code = ah_code,
    php_error_type = php_error_type,
    message_template = msg,
    parse_ok = parse_ok
  )[seq_len(n), ]
}
