test_that("combined lines are split into fields", {
  req <- fixture_requests()
  first <- req[1, ]

  expect_true(first$parse_ok)
  expect_equal(first$ip, "172.68.1.10")
  expect_equal(first$time, as.POSIXct("2026-07-09 21:48:03", tz = "UTC"))
  expect_equal(first$method, "GET")
  expect_equal(first$path, "/")
  expect_equal(first$protocol, "HTTP/1.1")
  expect_equal(first$status, 200L)
  expect_equal(first$bytes, 616)
  expect_true(is.na(first$referer))
  expect_match(first$user_agent, "^Mozilla/5.0 \\(X11")
  expect_true(is.na(first$bytes_in))
})

test_that("the query string is split off the path", {
  req <- fixture_requests()
  robots <- req[which(req$path == "/robots.txt"), ]
  expect_equal(robots$query, "lang=en")
  expect_true(is.na(req$query[1]))
})

test_that("the %I %O %D suffix and escaped quotes are parsed", {
  req <- fixture_requests()
  search <- req[which(req$path == "/search"), ]

  expect_equal(search$query, 'q="quoted"')
  expect_equal(search$bytes, 0)
  expect_equal(search$bytes_in, 512)
  expect_equal(search$bytes_out, 0)
  expect_equal(search$duration_us, 1534)
})

test_that("a non-HTTP request line parses without method or path", {
  req <- fixture_requests()
  bad_request <- req[which(req$status == 400), ]

  expect_true(bad_request$parse_ok)
  expect_true(is.na(bad_request$method))
  expect_true(is.na(bad_request$path))
  expect_true(is.na(bad_request$user_agent))
})

test_that("lines that are not access-log lines keep a row with parse_ok = FALSE", {
  req <- fixture_requests()
  expect_equal(nrow(req), 9)
  expect_equal(sum(!req$parse_ok), 1)
  expect_true(is.na(req$status[!req$parse_ok]))
})

test_that("IPv6 client addresses are parsed", {
  line <- '2001:db8::7 - - [10/Jul/2026:05:00:00 +0000] "GET / HTTP/2.0" 200 616 "-" "curl/8.7.1"'
  req <- parse_access_log(line)

  expect_true(req$parse_ok)
  expect_equal(req$ip, "2001:db8::7")
  expect_equal(req$protocol, "HTTP/2.0")
})
