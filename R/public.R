# Helpers for the comparison with public datasets (KAP-64, RQ3).

#' Load the patterns of the crawler-user-agents list
#'
#' Reads the JSON file of the public
#' [crawler-user-agents](https://github.com/monperrus/crawler-user-agents)
#' list (MIT licence) and returns its `pattern` field. Each pattern is a
#' regular expression.
#'
#' @param path Path to `crawler-user-agents.json`.
#' @return Character vector of regular expressions.
#' @export
load_crawler_patterns <- function(path) {
  entries <- jsonlite::read_json(path, simplifyVector = FALSE)
  vapply(entries, function(e) as.character(e$pattern), character(1))
}

#' Match user agents against crawler patterns
#'
#' Tests each user agent against every pattern and returns `TRUE` when at
#' least one matches. Matching is case-sensitive, as the list's own README
#' and reference implementations use it. Patterns run through PCRE
#' (`perl = TRUE`), which accepts the syntax of the list. A pattern that is
#' not a valid regular expression is skipped with one warning. A missing user
#' agent never matches.
#'
#' Distinct user agents are matched once, so passing a full request column is
#' cheap.
#'
#' @param user_agent Character vector of user agent strings.
#' @param patterns Character vector of regular expressions, e.g. from
#'   [load_crawler_patterns()].
#' @return Logical vector, same length as `user_agent`.
#' @export
match_crawler_ua <- function(user_agent, patterns) {
  user_agent <- as.character(user_agent)
  uniq <- unique(user_agent[!is.na(user_agent)])
  hit <- rep(FALSE, length(uniq))

  valid <- vapply(patterns, function(pattern) {
    tryCatch({
      grepl(pattern, "", perl = TRUE)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
  }, logical(1))
  if (any(!valid)) {
    warning(sprintf("%d pattern(s) skipped: not a valid regular expression.", sum(!valid)), call. = FALSE)
  }

  for (pattern in patterns[valid]) {
    todo <- which(!hit)
    if (length(todo) == 0) break
    hit[todo[grepl(pattern, uniq[todo], perl = TRUE)]] <- TRUE
  }
  out <- hit[match(user_agent, uniq)]
  out[is.na(out)] <- FALSE
  out
}

#' Reduce user agents to a product family
#'
#' Strips versions and platform details so that user agents can be counted by
#' product. For strings that start with the legacy `Mozilla/5.0` token the
#' family is the `compatible; Name/x.y` product when there is one, otherwise
#' the browser (Edge, Opera, Firefox, Chrome, Safari). For all other strings
#' it is the leading product token (`curl/8.4.0` becomes `curl`).
#'
#' @param user_agent Character vector of user agent strings.
#' @return Character vector of families; `NA` stays `NA`.
#' @export
ua_family <- function(user_agent) {
  ua <- as.character(user_agent)
  fam <- rep(NA_character_, length(ua))
  ok <- !is.na(ua)

  compat <- stringr::str_match(ua, "compatible;\\s*([A-Za-z][A-Za-z0-9._-]*)")[, 2]
  browser <- dplyr::case_when(
    grepl("Edg/", ua, fixed = TRUE) ~ "Edge",
    grepl("OPR/", ua, fixed = TRUE) ~ "Opera",
    grepl("Firefox/", ua, fixed = TRUE) ~ "Firefox",
    grepl("Chrome/", ua, fixed = TRUE) ~ "Chrome",
    grepl("Safari/", ua, fixed = TRUE) ~ "Safari",
    .default = NA_character_
  )
  leading <- stringr::str_match(ua, "^\\s*([^/\\s;(]+)")[, 2]
  legacy <- ok & startsWith(ua, "Mozilla/")

  fam[ok] <- leading[ok]
  fam[legacy] <- dplyr::coalesce(compat[legacy], browser[legacy], "Mozilla-compatible")
  # Non-legacy strings may still carry a "compatible; Name" token.
  other <- ok & !legacy & !is.na(compat)
  fam[other] <- compat[other]
  fam
}

#' Read a Common Log Format access log
#'
#' Reads a plain or gzipped Common Log Format file such as the public
#' NASA-HTTP trace (no referer, no user agent). Old traces are not UTF-8, so
#' the bytes are read as Latin-1 and converted before
#' [parse_access_log()] splits the lines. `referer` and `user_agent` are `NA`.
#'
#' @param path Path to the log (`.gz` is fine).
#' @return The tibble of [parse_access_log()]. Times are in UTC, converted from
#'   the offset in each line.
#' @export
read_clf_log <- function(path) {
  lines <- suppressWarnings(readLines(path, warn = FALSE, encoding = "latin1"))
  lines <- iconv(lines, from = "latin1", to = "UTF-8", sub = "?")
  lines <- lines[nzchar(lines)]
  parse_access_log(lines)
}
