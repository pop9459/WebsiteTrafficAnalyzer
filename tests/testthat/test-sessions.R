make_req <- function(ip, ua, mins, class = "human", day = "2026-10-01") {
  tibble::tibble(
    ip_hash = ip,
    user_agent = ua,
    time = as.POSIXct(paste(day, "10:00:00"), tz = "UTC") + mins * 60,
    client_class = class
  )
}

test_that("sessions_per_day splits on gaps and groups by ip and user agent", {
  req <- dplyr::bind_rows(
    # client A: 3 requests, 10 min gap, then 40 min gap, then 1 request -> 2 sessions
    make_req("a", "ua1", c(0, 10, 50)),
    make_req("a", "ua1", 51, day = "2026-10-02"),
    # same ip, other user agent -> separate client
    make_req("a", "ua2", c(0, 5)),
    # a bot is ignored by default
    make_req("b", "ua1", c(0, 1, 2), class = "bot")
  )
  out <- sessions_per_day(req)
  expect_named(out, c("day", "sessions", "clients", "requests", "median_session_requests"))
  d1 <- out[out$day == as.Date("2026-10-01"), ]
  expect_equal(d1$sessions, 3)
  expect_equal(d1$clients, 2)
  expect_equal(d1$requests, 5)
  expect_equal(d1$median_session_requests, 2)
  d2 <- out[out$day == as.Date("2026-10-02"), ]
  expect_equal(c(d2$sessions, d2$clients, d2$requests), c(1, 1, 1))
})

test_that("gap_minutes and classes are honoured", {
  req <- dplyr::bind_rows(
    make_req("a", "ua1", c(0, 10, 50)),
    make_req("b", "ua1", c(0, 1, 2), class = "bot")
  )
  expect_equal(sessions_per_day(req, gap_minutes = 60)$sessions, 1)
  expect_equal(sessions_per_day(req, gap_minutes = 5)$sessions, 3)
  both <- sessions_per_day(req, classes = c("human", "bot"))
  expect_equal(both$requests, 6)
  expect_equal(both$clients, 2)
})

test_that("a gap of exactly gap_minutes starts a new session", {
  req <- make_req("a", "ua1", c(0, 30))
  expect_equal(sessions_per_day(req)$sessions, 2)
})

test_that("a session is counted on the day it starts", {
  req <- tibble::tibble(
    ip_hash = "a", user_agent = "ua1", client_class = "human",
    time = as.POSIXct(c("2026-10-01 23:50:00", "2026-10-02 00:10:00"), tz = "UTC")
  )
  out <- sessions_per_day(req)
  expect_equal(nrow(out), 1)
  expect_equal(out$day, as.Date("2026-10-01"))
  expect_equal(out$requests, 2)
})

test_that("empty input gives an empty tibble with the right columns", {
  out <- sessions_per_day(make_req("a", "ua1", 0, class = "bot"))
  expect_equal(nrow(out), 0)
  expect_named(out, c("day", "sessions", "clients", "requests", "median_session_requests"))
})
