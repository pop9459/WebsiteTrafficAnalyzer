#' Per-client behaviour features
#'
#' Builds one row per `ip_hash` from direct-to-origin requests only
#' (`via_cloudflare == FALSE`). Cloudflare edge addresses are shared by many
#' visitors, so per-address behaviour would mix them. The features describe
#' behaviour, not the rule-based label, so they can be used to check
#' `client_class` with an unsupervised method (see
#' `analysis/cluster_validation.R`).
#'
#' @param requests A tibble from the pipeline with `time`, `ip_hash`,
#'   `via_cloudflare`, `path`, `status`, `user_agent`, `probe_family` and
#'   `client_class`.
#' @return A tibble with one row per client: `ip_hash`, `n_requests`
#'   (`log1p`), `active_days`, `share_4xx`, `share_probe` (share of requests
#'   whose `probe_family` is not `"none"`), `distinct_paths_ratio`,
#'   `share_no_ua`, `mean_requests_per_active_hour` (`log1p`), `share_night`
#'   (00:00-05:59 UTC) and `majority_class` (most common `client_class`, ties
#'   broken alphabetically; a label, not a clustering feature).
#' @export
client_features <- function(requests) {
  d <- requests[!is.na(requests$via_cloudflare) & !requests$via_cloudflare, ]
  empty <- tibble::tibble(
    ip_hash = character(), n_requests = double(), active_days = double(),
    share_4xx = double(), share_probe = double(),
    distinct_paths_ratio = double(), share_no_ua = double(),
    mean_requests_per_active_hour = double(), share_night = double(),
    majority_class = character()
  )
  if (nrow(d) == 0) {
    return(empty)
  }
  d$hour_key <- format(d$time, "%Y-%m-%d %H", tz = "UTC")
  d$day_key <- format(d$time, "%Y-%m-%d", tz = "UTC")
  d$night <- as.integer(format(d$time, "%H", tz = "UTC")) < 6

  # Majority class: count per (client, class), then alphabetical tie-break.
  majority <- d |>
    dplyr::count(.data$ip_hash, .data$client_class) |>
    dplyr::arrange(.data$ip_hash, dplyr::desc(.data$n), .data$client_class) |>
    dplyr::distinct(.data$ip_hash, .keep_all = TRUE) |>
    dplyr::select("ip_hash", majority_class = "client_class")

  d |>
    dplyr::group_by(.data$ip_hash) |>
    dplyr::summarise(
      n = dplyr::n(),
      active_days = dplyr::n_distinct(.data$day_key),
      share_4xx = mean(.data$status >= 400 & .data$status < 500, na.rm = TRUE),
      share_probe = mean(.data$probe_family != "none", na.rm = TRUE),
      distinct_paths_ratio = dplyr::n_distinct(.data$path) / dplyr::n(),
      share_no_ua = mean(is.na(.data$user_agent)),
      mean_requests_per_active_hour = log1p(dplyr::n() / dplyr::n_distinct(.data$hour_key)),
      share_night = mean(.data$night),
      .groups = "drop"
    ) |>
    dplyr::mutate(n_requests = log1p(.data$n), active_days = as.double(.data$active_days)) |>
    dplyr::left_join(majority, by = "ip_hash") |>
    dplyr::select(dplyr::all_of(names(empty)))
}
