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
