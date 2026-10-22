patterns <- c("Googlebot\\/", "bingbot", "^Wget", "(unclosed")

test_that("match_crawler_ua flags user agents that match any pattern", {
  ua <- c(
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (Windows NT 10.0) Chrome/120.0 Safari/537.36",
    "Wget/1.21",
    "Mozilla/5.0 (compatible; bingbot/2.0)"
  )
  expect_equal(suppressWarnings(match_crawler_ua(ua, patterns)), c(TRUE, FALSE, TRUE, TRUE))
})

test_that("matching is case-sensitive, like the list's own convention", {
  expect_false(match_crawler_ua("BINGBOT/2.0", "bingbot"))
  expect_true(match_crawler_ua("bingbot/2.0", "bingbot"))
})

test_that("missing user agents never match", {
  expect_equal(match_crawler_ua(c(NA, "Wget/1"), "^Wget"), c(FALSE, TRUE))
})

test_that("an invalid regex is skipped with a warning, the rest still match", {
  expect_warning(res <- match_crawler_ua("bingbot/2.0", patterns), "1 pattern")
  expect_true(res)
})

test_that("empty inputs give empty or all-FALSE results", {
  expect_equal(match_crawler_ua(character(), patterns[1]), logical())
  expect_equal(match_crawler_ua(c("a", "b"), character()), c(FALSE, FALSE))
})

test_that("repeated user agents get the same answer", {
  ua <- rep(c("bingbot/2.0", "curl/8.0"), 3)
  expect_equal(match_crawler_ua(ua, "bingbot"), rep(c(TRUE, FALSE), 3))
})

test_that("load_crawler_patterns reads the pattern field of the JSON list", {
  path <- withr::local_tempfile(fileext = ".json")
  writeLines(
    '[{"pattern":"Googlebot\\\\/","url":"x","instances":[]},{"pattern":"bingbot","instances":["a"]}]',
    path
  )
  expect_equal(load_crawler_patterns(path), c("Googlebot\\/", "bingbot"))
})

test_that("ua_family strips versions and keeps the product name", {
  expect_equal(ua_family("Googlebot/2.1 (+http://www.google.com/bot.html)"), "Googlebot")
  expect_equal(ua_family("Mozilla/5.0 (compatible; bingbot/2.0; +http://x)"), "bingbot")
  expect_equal(ua_family("python-requests/2.31.0"), "python-requests")
  expect_equal(ua_family("Go-http-client/1.1"), "Go-http-client")
  expect_equal(ua_family("curl/8.4.0"), "curl")
  expect_equal(ua_family(NA_character_), NA_character_)
})

test_that("ua_family reports plain browsers by browser name", {
  chrome <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  firefox <- "Mozilla/5.0 (X11; Linux x86_64; rv:152.0) Gecko/20100101 Firefox/152.0"
  expect_equal(ua_family(chrome), "Chrome")
  expect_equal(ua_family(firefox), "Firefox")
})

test_that("Common Log Format lines (no referer, no user agent) parse", {
  lines <- c(
    '199.72.81.55 - - [01/Jul/1995:00:00:01 -0400] "GET /history/apollo/ HTTP/1.0" 200 6245',
    'host.example - - [03/Jul/1995:02:41:15 -0400] "GET /images/ HTTP/1.0" 404 -'
  )
  p <- parse_access_log(lines)
  expect_true(all(p$parse_ok))
  expect_equal(p$status, c(200L, 404L))
  expect_equal(p$bytes, c(6245, 0))
  expect_equal(p$time[1], as.POSIXct("1995-07-01 04:00:01", tz = "UTC"))
  expect_true(all(is.na(p$user_agent)))
})

test_that("read_clf_log copes with Latin-1 bytes", {
  path <- withr::local_tempfile(fileext = ".log")
  con <- file(path, "wb")
  writeBin(c(
    charToRaw('h.example - - [01/Jul/1995:00:00:01 -0400] "GET /caf'), as.raw(0xe9),
    charToRaw(' HTTP/1.0" 200 10\n')
  ), con)
  close(con)
  p <- read_clf_log(path)
  expect_equal(nrow(p), 1L)
  expect_true(p$parse_ok)
  expect_equal(p$status, 200L)
})
