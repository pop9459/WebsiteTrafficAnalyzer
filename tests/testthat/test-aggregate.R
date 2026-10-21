# Six hand-made requests on two days, so every expected value can be
# checked by hand.
agg_requests <- function() {
  tibble::tibble(
    time = as.POSIXct(c(
      "2026-10-01 10:05:00", "2026-10-01 10:40:00", "2026-10-01 11:00:00",
      "2026-10-02 09:00:00", "2026-10-02 09:30:00", "2026-10-02 23:59:59"
    ), tz = "UTC"),
    ip_hash = c("a", "a", "b", "c", "c", "d"),
    client_class = c("human", "human", "scanner", "scanner", "scanner", "bot"),
    status = c(200L, 304L, 404L, 404L, 200L, 503L),
    bytes = c(1000, 0, 500, 500, 2000, NA),
    bytes_in = c(NA, NA, NA, 300, 400, NA),
    path = c("/", "/", "/.env", "/.env", "/.git/config", "/robots.txt"),
    user_agent = c(
      "Mozilla/5.0 (X11; Linux) Firefox/130.0", "Mozilla/5.0 (X11; Linux) Firefox/130.0",
      "zgrab/0.x", "zgrab/0.x", "zgrab/0.x", "Googlebot/2.1"
    ),
    referer = c("https://www.google.com/search?q=x", NA, NA, NA, NA, "http://203.0.113.9/")
  )
}

test_that("traffic_by_period counts requests, clients and bytes per day and class", {
  out <- traffic_by_period(agg_requests(), "day")
  expect_equal(out$period, as.Date(c("2026-10-01", "2026-10-01", "2026-10-02", "2026-10-02")))
  expect_equal(out$client_class, c("human", "scanner", "bot", "scanner"))
  expect_equal(out$requests, c(2L, 1L, 1L, 2L))
  expect_equal(out$clients, c(1L, 1L, 1L, 1L))
  expect_equal(out$bytes_out, c(1000, 500, NA, 2500))
  expect_equal(out$bytes_in, c(NA, NA, NA, 700))
})

test_that("traffic_by_period floors to the UTC hour", {
  out <- traffic_by_period(agg_requests(), "hour")
  expect_equal(out$period[1], as.POSIXct("2026-10-01 10:00:00", tz = "UTC"))
  expect_equal(out$requests, c(2L, 1L, 2L, 1L))
})

test_that("status_by_period gives counts and the share within each day", {
  out <- status_by_period(agg_requests(), "day")
  expect_equal(out$status_class, c("2xx", "3xx", "4xx", "2xx", "4xx", "5xx"))
  expect_equal(out$requests, rep(1L, 6))
  expect_equal(out$share, rep(1 / 3, 6))
})

test_that("top_values ranks values per class and drops rare ones", {
  out <- top_values(agg_requests(), "path", n = 1, min_requests = 2)
  expect_equal(out$client_class, c("human", "scanner"))
  expect_equal(out$value, c("/", "/.env"))
  expect_equal(out$requests, c(2L, 2L))
})

test_that("top_values cuts referers to the host and masks IP addresses", {
  out <- top_values(agg_requests(), "referer", min_requests = 1)
  expect_equal(out$value, c("<ip>", "www.google.com"))
})

test_that("top_values refuses columns that are not safe to publish", {
  expect_error(top_values(agg_requests(), "ip_hash"), "must be one of")
})

test_that("export_dashboard_json writes aggregates only", {
  path <- withr::local_tempfile(fileext = ".json")
  export_dashboard_json(agg_requests(), path, min_requests = 1)
  text <- paste(readLines(path, warn = FALSE), collapse = "")
  out <- jsonlite::fromJSON(path)

  expect_named(out, c(
    "generated_at", "from", "to", "totals", "daily", "status_daily",
    "top_paths", "top_user_agents", "top_referrers"
  ))
  expect_equal(out$from, "2026-10-01T10:05:00Z")
  expect_equal(sum(out$totals$requests), 6)
  expect_equal(nrow(out$daily), 4)
  expect_false(grepl("ip_hash", text, fixed = TRUE))
  expect_false(grepl("203.0.113.9", text, fixed = TRUE))
})
