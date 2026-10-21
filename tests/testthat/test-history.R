json_line <- function(log, stream = "stdout") {
  jsonlite::toJSON(
    list(log = paste0(log, "\n"), stream = stream, time = "2025-09-01T10:00:00.000000000Z"),
    auto_unbox = TRUE
  ) |> as.character()
}

apache <- function(ip, day, path, status, bytes, ua = "Mozilla/5.0 (X11; Linux x86_64) Firefox/150.0") {
  sprintf('%s - - [%s:10:00:00 +0000] "GET %s HTTP/1.1" %d %d "-" "%s"', ip, day, path, status, bytes, ua)
}

history_lines <- function() {
  c(
    json_line(apache("192.0.2.1", "01/Sep/2025", "/", 200, 1000)),
    json_line(apache("192.0.2.1", "01/Sep/2025", "/about", 200, 500)),
    json_line(apache("192.0.2.2", "01/Sep/2025", "/.env", 404, 300, "curl/8.0")),
    json_line(apache("192.0.2.2", "02/Sep/2025", "/.env", 404, 200, "curl/8.0")),
    json_line(apache("192.0.2.3", "02/Sep/2025", "/", 200, 700)),
    "{this is not json",
    json_line("AH00558: apache2: Could not reliably determine the server name", "stderr"),
    json_line("this is not an apache line")
  )
}

test_that("aggregate_log_chunk counts lines and aggregates per day", {
  res <- aggregate_log_chunk(history_lines(), "test-salt")

  expect_equal(res$counters$lines, 8)
  expect_equal(res$counters$json_failed, 1)
  expect_equal(res$counters$stdout, 6)
  expect_equal(res$counters$stderr, 1)
  expect_equal(res$counters$parse_ok, 5)
  expect_equal(res$counters$parse_failed, 1)
  expect_equal(res$counters$min_time, as.POSIXct("2025-09-01 10:00:00", tz = "UTC"))
  expect_equal(res$counters$max_time, as.POSIXct("2025-09-02 10:00:00", tz = "UTC"))

  by_class <- res$by_class
  expect_named(by_class, c("day", "client_class", "requests", "bytes"))
  expect_equal(sum(by_class$requests), 5)
  expect_equal(sum(by_class$bytes), 1000 + 500 + 300 + 200 + 700)
  sc <- by_class[by_class$client_class == "scanner", ]
  expect_equal(sc$requests[sc$day == as.Date("2025-09-01")], 1)
  expect_equal(sc$bytes[sc$day == as.Date("2025-09-02")], 200)

  expect_equal(sum(res$by_status$requests[res$by_status$status_class == "4xx"]), 2)
  expect_equal(sum(res$by_status$requests[res$by_status$status_class == "2xx"]), 3)
  expect_equal(sum(res$by_probe$requests[res$by_probe$probe_family == "env"]), 2)

  expect_named(res$pairs, c("day", "ip_hash"))
  expect_equal(nrow(res$pairs), 4)
  expect_false(any(grepl("192.0.2", unlist(res$pairs))))
})

test_that("aggregate_log_chunk handles chunks without usable lines", {
  res <- aggregate_log_chunk(c("garbage", json_line("x", "stderr")), "test-salt")
  expect_equal(res$counters$lines, 2)
  expect_equal(res$counters$parse_ok, 0)
  expect_equal(nrow(res$by_class), 0)
  expect_equal(nrow(res$pairs), 0)
  expect_true(is.na(res$counters$min_time))
})

test_that("combine_history_chunks equals one big chunk for additive parts", {
  lines <- history_lines()
  whole <- aggregate_log_chunk(lines, "test-salt")
  # Split so that the same client appears in both chunks (clients must not double count).
  parts <- list(
    aggregate_log_chunk(lines[1:3], "test-salt"),
    aggregate_log_chunk(lines[4:8], "test-salt")
  )
  comb <- combine_history_chunks(parts)

  expect_equal(comb$counters$lines, 8)
  expect_equal(comb$counters$json_failed, 1)
  expect_equal(comb$counters$parse_ok, 5)
  expect_equal(comb$counters$min_time, whole$counters$min_time)
  expect_equal(comb$counters$max_time, whole$counters$max_time)
  expect_equal(sum(comb$by_class$requests), 5)
  expect_equal(sum(comb$by_class$bytes), 2700)
  expect_equal(sum(comb$by_status$requests), 5)
  expect_equal(sum(comb$by_probe$requests), 5)
  expect_named(comb$clients, c("day", "clients"))
  expect_equal(comb$clients$clients, c(2, 2))
  expect_null(comb$pairs)
  expect_equal(nrow(comb$by_class), nrow(dplyr::distinct(comb$by_class, day, client_class)))
})

test_that("combine_history_chunks can keep pairs for incremental folding", {
  lines <- history_lines()
  a <- combine_history_chunks(list(aggregate_log_chunk(lines[1:3], "s")), keep_pairs = TRUE)
  b <- combine_history_chunks(list(a, aggregate_log_chunk(lines[4:8], "s")))
  expect_equal(b$clients$clients, c(2, 2))
  expect_equal(b$counters$lines, 8)
})

test_that("Flask/werkzeug-style lines count as parse failures, silently", {
  lines <- c(
    json_line('127.0.0.1 - - [12/Sep/2025 10:00:44] "POST /hook HTTP/1.1" 200 -'),
    json_line(" * Running on http://0.0.0.0:5000"),
    json_line(apache("192.0.2.1", "12/Sep/2025", "/", 200, 10))
  )
  expect_no_warning(res <- aggregate_log_chunk(lines, "test-salt"))
  expect_equal(res$counters$stdout, 3)
  expect_equal(res$counters$parse_ok, 1)
  expect_equal(res$counters$parse_failed, 2)
  expect_equal(sum(res$by_class$requests), 1)
})
