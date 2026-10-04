test_that("Cloudflare IPv4 and IPv6 addresses are recognised", {
  ips <- c("172.68.213.34", "162.158.1.1", "104.23.255.255", "2a06:98c7::1", "2606:4700:10::6816:1")
  expect_equal(in_cloudflare(ips), rep(TRUE, 5))
})

test_that("other addresses are not Cloudflare", {
  ips <- c("192.0.2.1", "172.72.0.1", "104.32.0.1", "2001:db8::1", "::1", "127.0.0.1")
  expect_equal(in_cloudflare(ips), rep(FALSE, 6))
})

test_that("invalid addresses give NA", {
  expect_equal(in_cloudflare(c("not-an-ip", "300.1.1.1", NA)), c(NA, NA, NA))
})
