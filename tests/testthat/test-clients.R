# Hand-made fixture: client "a" (4 requests, 2 days, 2 active hours),
# client "b" (1 request) and a Cloudflare client "c" that must be dropped.
client_requests <- function() {
  tibble::tibble(
    time = as.POSIXct(c(
      "2026-10-01 10:00:00", "2026-10-01 10:30:00",
      "2026-10-02 02:00:00", "2026-10-02 02:10:00",
      "2026-10-01 12:00:00", "2026-10-01 13:00:00"
    ), tz = "UTC"),
    ip_hash = c("a", "a", "a", "a", "b", "c"),
    via_cloudflare = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
    path = c("/", "/", "/x", "/y", "/.env", "/"),
    status = c(200L, 404L, 404L, 200L, 404L, 200L),
    user_agent = c("Firefox", "Firefox", NA, "Firefox", NA, "Firefox"),
    probe_family = c("none", "none", "wordpress", "none", "env", "none"),
    client_class = c("human", "human", "scanner", "human", "scanner", "human")
  )
}

test_that("client_features() keeps one row per direct client", {
  f <- client_features(client_requests())
  expect_equal(sort(f$ip_hash), c("a", "b"))
})

test_that("client_features() computes the features by hand-checked values", {
  f <- client_features(client_requests())
  a <- f[f$ip_hash == "a", ]
  expect_equal(a$n_requests, log1p(4))
  expect_equal(a$active_days, 2)
  expect_equal(a$share_4xx, 0.5)
  expect_equal(a$share_probe, 0.25)
  expect_equal(a$distinct_paths_ratio, 3 / 4)
  expect_equal(a$share_no_ua, 0.25)
  expect_equal(a$mean_requests_per_active_hour, log1p(2))
  expect_equal(a$share_night, 0.5)
  expect_equal(a$majority_class, "human")
  b <- f[f$ip_hash == "b", ]
  expect_equal(b$share_4xx, 1)
  expect_equal(b$share_no_ua, 1)
  expect_equal(b$majority_class, "scanner")
})

test_that("client_features() breaks majority ties alphabetically", {
  r <- client_requests()[1:2, ]
  r$client_class <- c("human", "bot")
  expect_equal(client_features(r)$majority_class, "bot")
})

test_that("client_features() returns an empty tibble without direct traffic", {
  r <- client_requests()
  r$via_cloudflare <- TRUE
  expect_equal(nrow(client_features(r)), 0)
})
