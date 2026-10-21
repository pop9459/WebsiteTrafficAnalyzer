# Aggregates for the dashboard (KAP-56). Every function returns counts only:
# no ip_hash, no full referer, no IP address leaves this file.

ipv4_regex <- "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b"

# NA when the log format did not record the field at all (e.g. %I before
# 7 Oct 2026), instead of a misleading 0.
sum_or_na <- function(x) {
  if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
}

floor_period <- function(time, unit) {
  if (unit == "day") {
    return(as.Date(time, tz = "UTC"))
  }
  as.POSIXct(floor(as.numeric(time) / 3600) * 3600, origin = "1970-01-01", tz = "UTC")
}

# "https://www.google.com/search?q=x" -> "www.google.com". Values without a
# scheme (the committed sample already stores hosts) are kept as they are.
referer_host <- function(referer) {
  tolower(sub("^[a-z][a-z0-9+.-]*://([^/?#]+).*$", "\\1", referer, ignore.case = TRUE))
}

#' Count requests, clients and bytes per period and client class
#'
#' @param requests Classified requests from [classify_requests()], with the
#'   columns `time`, `ip_hash`, `client_class`, `bytes` and `bytes_in`.
#' @param unit `"day"` or `"hour"`, both in UTC.
#' @return A tibble with one row per `period` and `client_class`: `requests`,
#'   `clients` (distinct `ip_hash`; Cloudflare edge addresses count as one
#'   client each), `bytes_out` (sum of the response size `%b`) and `bytes_in`
#'   (sum of `%I`, `NA` when the log format did not record it).
#' @export
traffic_by_period <- function(requests, unit = c("day", "hour")) {
  unit <- match.arg(unit)
  requests |>
    dplyr::mutate(period = floor_period(.data$time, unit)) |>
    dplyr::summarise(
      requests = dplyr::n(),
      clients = dplyr::n_distinct(.data$ip_hash),
      bytes_out = sum_or_na(.data$bytes),
      bytes_in = sum_or_na(.data$bytes_in),
      .by = c("period", "client_class")
    ) |>
    dplyr::arrange(.data$period, .data$client_class)
}

#' Count status-code classes per period
#'
#' The error rate of a period is the summed `share` of `4xx` and `5xx`.
#'
#' @inheritParams traffic_by_period
#' @return A tibble with `period`, `status_class` (`"2xx"` ... `"5xx"`),
#'   `requests` and `share` (of all requests in that period).
#' @export
status_by_period <- function(requests, unit = c("day", "hour")) {
  unit <- match.arg(unit)
  requests |>
    dplyr::mutate(
      period = floor_period(.data$time, unit),
      status_class = paste0(.data$status %/% 100, "xx")
    ) |>
    dplyr::summarise(requests = dplyr::n(), .by = c("period", "status_class")) |>
    dplyr::mutate(share = .data$requests / sum(.data$requests), .by = "period") |>
    dplyr::arrange(.data$period, .data$status_class)
}

#' Most frequent paths, user agents or referer hosts per client class
#'
#' Referers are cut down to their host, and IPv4 addresses in any value are
#' replaced by `<ip>`. Values seen fewer than `min_requests` times are
#' dropped, so rare (possibly identifying) strings are never published.
#'
#' @inheritParams traffic_by_period
#' @param column One of `"path"`, `"user_agent"` or `"referer"`.
#' @param n Number of values to keep per class.
#' @param min_requests Minimum number of requests for a value to be listed.
#' @return A tibble with `client_class`, `value` and `requests`.
#' @export
top_values <- function(requests, column, n = 10, min_requests = 5) {
  column <- rlang::arg_match(column, c("path", "user_agent", "referer"))
  values <- requests[[column]]
  if (column == "referer") values <- referer_host(values)
  tibble::tibble(client_class = requests$client_class, value = gsub(ipv4_regex, "<ip>", values)) |>
    dplyr::filter(!is.na(.data$value)) |>
    dplyr::summarise(requests = dplyr::n(), .by = c("client_class", "value")) |>
    dplyr::filter(.data$requests >= min_requests) |>
    dplyr::arrange(.data$client_class, dplyr::desc(.data$requests), .data$value) |>
    dplyr::slice_head(n = n, by = "client_class") |>
    dplyr::arrange(.data$client_class, dplyr::desc(.data$requests), .data$value)
}

#' Write the dashboard aggregates to a JSON file
#'
#' @inheritParams top_values
#' @param path Output file; parent folders are created.
#' @param top_n Number of top values per class in the `top_*` lists.
#' @return `path`, invisibly.
#' @export
export_dashboard_json <- function(requests, path, top_n = 10, min_requests = 5) {
  iso <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  out <- list(
    generated_at = iso(Sys.time()),
    from = iso(min(requests$time)),
    to = iso(max(requests$time)),
    totals = requests |>
      dplyr::summarise(requests = dplyr::n(), .by = "client_class") |>
      dplyr::arrange(dplyr::desc(.data$requests)),
    daily = traffic_by_period(requests, "day"),
    status_daily = status_by_period(requests, "day"),
    top_paths = top_values(requests, "path", top_n, min_requests),
    top_user_agents = top_values(requests, "user_agent", top_n, min_requests),
    top_referrers = top_values(requests, "referer", top_n, min_requests)
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    out, path,
    auto_unbox = TRUE, dataframe = "rows", Date = "ISO8601",
    POSIXt = "ISO8601", na = "null", digits = NA
  )
  invisible(path)
}
