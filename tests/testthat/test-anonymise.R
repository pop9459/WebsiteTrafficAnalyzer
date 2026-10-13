test_that("hashes are deterministic and depend on the salt", {
  ips <- c("192.0.2.1", "192.0.2.2", "192.0.2.1", NA)
  a <- hash_ip(ips, "salt-a")

  expect_equal(a[1], a[3])
  expect_false(a[1] == a[2])
  expect_true(is.na(a[4]))
  expect_match(a[1:3], "^[0-9a-f]{16}$")
  expect_false(hash_ip("192.0.2.1", "salt-b") == a[1])
})

test_that("an empty salt is refused", {
  expect_error(hash_ip("192.0.2.1", ""), "salt")
})

test_that("anonymise_requests removes the IP and personal fields", {
  anon <- anonymise_requests(fixture_requests(), "test-salt")

  expect_false(any(c("ip", "ident", "user") %in% names(anon)))
  expect_equal(names(anon)[1:2], c("ip_hash", "via_cloudflare"))
  expect_false(any(grepl("192.0.2.", unlist(anon), fixed = TRUE)))
  expect_equal(anon$via_cloudflare[1], TRUE)
  expect_equal(anon$via_cloudflare[3], FALSE)
})

test_that("get_salt prefers WTA_SALT, then the salt file", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "salt")

  withr::local_envvar(WTA_SALT = "from-env")
  expect_equal(get_salt(path = path), "from-env")

  withr::local_envvar(WTA_SALT = "")
  expect_error(get_salt(path = path), "No salt")

  salt <- get_salt(create = TRUE, path = path)
  expect_match(salt, "^[0-9a-f]{64}$")
  expect_equal(get_salt(path = path), salt)
})

test_that("via_cloudflare uses the connecting address when peer_ip is logged", {
  req <- parse_access_log(c(
    # visitor behind Cloudflare: real IP in `ip`, Cloudflare edge as the peer
    paste0('198.51.100.9 - - [10/Jul/2026:07:00:00 +0000] "GET / HTTP/1.1" 200 1 ',
           '"-" "curl/8.7.1" 100 200 300 172.68.1.10'),
    # direct hit: the peer is the visitor itself
    paste0('203.0.113.5 - - [10/Jul/2026:07:00:01 +0000] "GET /.env HTTP/1.1" 404 1 ',
           '"-" "curl/8.7.1" 100 200 300 203.0.113.5')
  ))
  anon <- anonymise_requests(req, "test-salt")

  expect_equal(anon$via_cloudflare, c(TRUE, FALSE))
  expect_false("peer_ip" %in% names(anon))
  expect_false(any(grepl("172.68.1.10|198.51.100.9|203.0.113.5", unlist(anon))))
})

test_that("the committed sample contains no IP addresses", {
  path <- test_path("../../data/sample/requests_sample.csv")
  skip_if_not(file.exists(path), "sample data is not part of the built package")

  sample <- readr::read_csv(path, col_types = readr::cols(.default = "c"))
  expect_false(any(c("ip", "peer_ip", "ident", "user") %in% names(sample)))
  expect_match(sample$ip_hash, "^[0-9a-f]{16}$")

  # Browser versions such as "Chrome/138.0.0.0" look like IPv4 addresses,
  # so the user agent is left out of the check.
  ipv4 <- "(?<![0-9.])([0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9.])"
  free_text <- unlist(sample[c("path", "referer")], use.names = FALSE)
  expect_false(any(grepl(ipv4, free_text, perl = TRUE)))
})
