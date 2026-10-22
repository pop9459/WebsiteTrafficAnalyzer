#' Estimate visits (sessions) per day
#'
#' A session is a run of requests from one client with no gap of
#' `gap_minutes` or more between two consecutive requests. A client is one
#' `ip_hash` together with one `user_agent`. A session belongs to the day of
#' its first request, and `requests` and `clients` count what falls in the
#' sessions that start that day.
#'
#' Requests that came through Cloudflare (`via_cloudflare`) carry the address
#' of a shared Cloudflare edge server instead of the visitor's. Several
#' visitors with the same browser can therefore merge into one client, so
#' sessions for those requests are approximate (an under-count when visitors
#' overlap in time).
#'
#' @param requests Classified requests with `ip_hash`, `user_agent`, `time`
#'   and `client_class` (see [classify_requests()]).
#' @param gap_minutes A gap of at least this many minutes starts a new
#'   session.
#' @param classes Client classes to include.
#' @return A tibble with one row per day: `day` (UTC date), `sessions`,
#'   `clients` (distinct ip_hash and user agent pairs), `requests` and
#'   `median_session_requests`.
#' @export
sessions_per_day <- function(requests, gap_minutes = 30, classes = "human") {
  kept <- requests[requests$client_class %in% classes & !is.na(requests$time), ]
  if (nrow(kept) == 0) {
    return(tibble::tibble(
      day = as.Date(character()), sessions = integer(), clients = integer(),
      requests = integer(), median_session_requests = numeric()
    ))
  }
  kept <- kept[order(kept$ip_hash, kept$user_agent, kept$time), ]

  # Rows are sorted, so a new client or a long gap marks the start of a session.
  key <- paste(kept$ip_hash, kept$user_agent)
  new_client <- c(TRUE, key[-1] != key[-length(key)])
  gap <- c(Inf, diff(as.numeric(kept$time)) / 60)
  kept$key <- key
  kept$session <- cumsum(new_client | gap >= gap_minutes)

  sessions <- kept |>
    dplyr::group_by(.data$session) |>
    dplyr::summarise(
      day = as.Date(min(.data$time), tz = "UTC"),
      client = dplyr::first(.data$key),
      n = dplyr::n(),
      .groups = "drop"
    )

  sessions |>
    dplyr::group_by(.data$day) |>
    dplyr::summarise(
      sessions = dplyr::n(),
      clients = dplyr::n_distinct(.data$client),
      requests = sum(.data$n),
      median_session_requests = stats::median(.data$n),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      sessions = as.integer(.data$sessions),
      clients = as.integer(.data$clients),
      requests = as.integer(.data$requests)
    )
}
