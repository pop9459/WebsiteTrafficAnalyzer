# A tiny synthetic lookup table: documentation ranges only, no real database.
write_test_geo <- function(dir) {
  writeLines(c(
    "192.0.2.0,192.0.2.255,NL",
    "198.51.100.0,198.51.100.255,DE",
    "2001:db8::,2001:db8:ffff:ffff:ffff:ffff:ffff:ffff,SK"
  ), file.path(dir, "dbip-country-lite-test.csv"))
  writeLines(c(
    "192.0.2.0,192.0.2.127,64500,\"Example Hosting, Inc.\"",
    "198.51.100.0,198.51.100.255,64501,Example ISP",
    "2001:db8::,2001:db8:ffff:ffff:ffff:ffff:ffff:ffff,64502,Example v6"
  ), file.path(dir, "dbip-asn-lite-test.csv"))
  dir
}

test_geo_db <- function() {
  load_geo_db(write_test_geo(withr::local_tempdir(.local_envir = parent.frame())))
}

test_that("geo_dir honours WTA_GEO_DIR", {
  withr::local_envvar(WTA_GEO_DIR = "/some/where")
  expect_equal(geo_dir(), "/some/where")
  withr::local_envvar(WTA_GEO_DIR = "")
  expect_match(geo_dir(), "websitetrafficanalyzer/geo$")
})

test_that("geo_lookup resolves IPv4 and IPv6, vectorised, NA when unknown", {
  db <- test_geo_db()
  ips <- c("192.0.2.5", "192.0.2.200", "198.51.100.1", "203.0.113.9",
           "2001:db8::1", "2001:db9::1", NA, "not-an-ip")
  res <- geo_lookup(ips, db)

  expect_s3_class(res, "tbl_df")
  expect_equal(names(res), c("country", "asn", "as_org"))
  expect_equal(res$country, c("NL", "NL", "DE", NA, "SK", NA, NA, NA))
  expect_equal(res$asn, c(64500L, NA, 64501L, NA, 64502L, NA, NA, NA))
  expect_equal(res$as_org[1], "Example Hosting, Inc.")
  expect_equal(res$as_org[3], "Example ISP")
})

test_that("load_geo_db fails clearly when files are missing", {
  expect_error(load_geo_db(withr::local_tempdir()), "geo")
})

test_that("anonymise_requests geolocates the visitor, never a Cloudflare edge", {
  db <- test_geo_db()
  req <- parse_access_log(c(
    # Extended format: visitor 198.51.100.9 reached us through edge 172.68.1.10.
    paste0('198.51.100.9 - - [10/Jul/2026:07:00:00 +0000] "GET / HTTP/1.1" 200 1 ',
           '"-" "curl/8.7.1" 100 200 300 172.68.1.10'),
    paste0('192.0.2.5 - - [10/Jul/2026:07:00:01 +0000] "GET /.env HTTP/1.1" 404 1 ',
           '"-" "curl/8.7.1" 100 200 300 192.0.2.5'),
    # Old combined format: only the edge address is logged.
    '172.68.1.10 - - [10/Jul/2026:07:00:02 +0000] "GET / HTTP/1.1" 200 1 "-" "curl/8.7.1"'
  ))
  anon <- anonymise_requests(req, "test-salt", geo_db = db)

  expect_equal(anon$via_cloudflare, c(TRUE, FALSE, TRUE))
  expect_equal(anon$country, c("DE", "NL", NA))
  expect_equal(anon$asn, c(64501L, 64500L, NA))
  expect_equal(anon$as_org, c("Example ISP", "Example Hosting, Inc.", NA))
  expect_false(any(grepl("198.51.100.9|192.0.2.5|172.68.1.10", unlist(anon))))
})

test_that("anonymise_requests falls back to NA geo fields without a database", {
  withr::local_envvar(WTA_GEO_DIR = withr::local_tempdir())
  geo_cache_clear()
  anon <- suppressMessages(anonymise_requests(fixture_requests(), "test-salt"))

  expect_true(all(c("country", "asn", "as_org") %in% names(anon)))
  expect_true(all(is.na(anon$country)))
  expect_type(anon$asn, "integer")
  expect_message(anonymise_requests(fixture_requests(), "test-salt"), NA)
})
