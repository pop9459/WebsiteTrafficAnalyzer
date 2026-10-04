test_that("json-file logs are read with stream and time", {
  raw <- read_raw_log(fixture_path("mini.json.log"))

  expect_named(raw, c("time", "stream", "line"))
  expect_equal(nrow(raw), 10)
  expect_equal(sum(raw$stream == "stderr"), 1)
  expect_false(any(grepl("\n", raw$line, fixed = TRUE)))
  expect_equal(raw$time[1], as.POSIXct("2026-07-09 21:43:32.269408", tz = "UTC"), tolerance = 1e-3)
})

test_that("gzipped files are read too", {
  gz <- withr::local_tempfile(fileext = ".log.gz")
  con <- gzfile(gz, "w")
  writeLines(readLines(fixture_path("mini.json.log")), con)
  close(con)

  expect_equal(read_raw_log(gz), read_raw_log(fixture_path("mini.json.log")))
})

test_that("docker logs --timestamps output is read", {
  path <- withr::local_tempfile()
  writeLines(c(
    '2026-07-09T21:48:03.100000000Z 192.0.2.1 - - [09/Jul/2026:21:48:03 +0000] "GET / HTTP/1.1" 200 616 "-" "-"',
    "2026-07-09T21:48:04.000000000Z AH00558: apache2: message"
  ), path)

  raw <- read_raw_log(path)
  expect_true(all(is.na(raw$stream)))
  expect_true(startsWith(raw$line[1], "192.0.2.1 "))
  expect_equal(format(raw$time[2], "%H:%M:%S"), "21:48:04")
})

test_that("plain access logs are read as stdout without time", {
  path <- withr::local_tempfile()
  writeLines('192.0.2.1 - - [09/Jul/2026:21:48:03 +0000] "GET / HTTP/1.1" 200 616 "-" "-"', path)

  raw <- read_raw_log(path)
  expect_equal(raw$stream, "stdout")
  expect_true(is.na(raw$time))
})

test_that("empty files give an empty tibble", {
  path <- withr::local_tempfile()
  writeLines(character(), path)
  expect_equal(nrow(read_raw_log(path)), 0)
})
