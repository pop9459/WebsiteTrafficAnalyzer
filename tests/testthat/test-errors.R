error_lines <- c(
  # 1 php warning with client, referer and file path
  "[Tue Oct 07 10:28:01.123456 2026] [php:warn] [pid 23] [client 203.0.113.5:4711] PHP Warning:  Undefined variable $x in /var/www/html/index.php on line 12, referer: https://kapsiar.sk/",
  # 2 core error with AH code and request path
  "[Tue Oct 07 10:29:02.000001 2026] [core:error] [pid 23:tid 140] [client 198.51.100.7:5555] AH00126: Invalid URI in request GET /%%%  HTTP/1.1",
  # 3 notice without client
  "[Tue Oct 07 10:28:00.500000 2026] [mpm_prefork:notice] [pid 1] AH00163: Apache/2.4.62 (Debian) PHP/8.2.20 configured -- resuming normal operations",
  # 4 non-bracketed AH line
  "AH00558: apache2: Could not reliably determine the server's fully qualified domain name, using 192.0.2.10. Set the 'ServerName' directive globally to suppress this message",
  # 5 garbage
  "this is not an apache line",
  # 6 php module error without AH code and without error type
  "[Wed Oct 08 01:02:03.000000 2026] [php:error] [pid 45:tid 99] [client 203.0.113.9:1] script '/var/www/html/wp-login.php' not found or unable to stat",
  # 7 fatal error in site file
  "[Wed Oct 08 02:00:00.000000 2026] [php:error] [pid 46] [client 192.0.2.44:80] PHP Fatal error:  Uncaught Error: Call to undefined function foo() in /var/www/html/phpContent/page.php:77",
  # 8 autoindex with directory
  "[Wed Oct 08 03:00:00.000000 2026] [autoindex:error] [pid 47:tid 1] [client 198.51.100.8:2] AH01276: Cannot serve directory /var/www/html/uploads/: No matching DirectoryIndex (index.php) found, and server-generated directory index forbidden by Options directive"
)

test_that("parse_error_log returns one row per line with the documented columns", {
  out <- parse_error_log(error_lines)
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), length(error_lines))
  expect_named(out, c("time", "module", "level", "ah_code", "php_error_type", "message_template", "parse_ok"))
  expect_s3_class(out$time, "POSIXct")
  expect_type(out$parse_ok, "logical")
})

test_that("php warning is parsed", {
  r <- parse_error_log(error_lines)[1, ]
  expect_equal(r$time, as.POSIXct("2026-10-07 10:28:01", tz = "UTC"), tolerance = 1)
  expect_equal(r$module, "php")
  expect_equal(r$level, "warn")
  expect_true(is.na(r$ah_code))
  expect_equal(r$php_error_type, "Warning")
  expect_match(r$message_template, "Undefined variable", fixed = TRUE)
  expect_match(r$message_template, "/var/www/html/index.php", fixed = TRUE)
  expect_false(grepl("on line 12", r$message_template, fixed = TRUE))
  expect_true(r$parse_ok)
})

test_that("core error keeps AH code and masks the request path", {
  r <- parse_error_log(error_lines)[2, ]
  expect_equal(r$module, "core")
  expect_equal(r$level, "error")
  expect_equal(r$ah_code, "AH00126")
  expect_true(is.na(r$php_error_type))
  expect_match(r$message_template, "<path>", fixed = TRUE)
  expect_false(grepl("%%%", r$message_template, fixed = TRUE))
})

test_that("notice without client parses and numbers become <n>", {
  r <- parse_error_log(error_lines)[3, ]
  expect_equal(r$module, "mpm_prefork")
  expect_equal(r$level, "notice")
  expect_equal(r$ah_code, "AH00163")
  expect_match(r$message_template, "Apache/<n>.<n>.<n>", fixed = TRUE)
  expect_true(r$parse_ok)
})

test_that("non-bracketed AH line is parsed with NA time", {
  r <- parse_error_log(error_lines)[4, ]
  expect_true(is.na(r$time))
  expect_true(is.na(r$module))
  expect_equal(r$ah_code, "AH00558")
  expect_match(r$message_template, "<s>", fixed = TRUE)
  expect_true(r$parse_ok)
})

test_that("garbage line is kept with parse_ok FALSE", {
  r <- parse_error_log(error_lines)[5, ]
  expect_false(r$parse_ok)
  expect_true(is.na(r$time) && is.na(r$module) && is.na(r$ah_code))
})

test_that("script-not-found lines group by template", {
  out <- parse_error_log(error_lines)
  expect_equal(out$message_template[6], "script <s> not found or unable to stat")
  expect_equal(out$module[6], "php")
})

test_that("php fatal error keeps file path but drops line number", {
  r <- parse_error_log(error_lines)[7, ]
  expect_equal(r$php_error_type, "Fatal error")
  expect_match(r$message_template, "/var/www/html/phpContent/page.php", fixed = TRUE)
  expect_false(grepl("77", r$message_template, fixed = TRUE))
})

test_that("directory paths in non-site messages become <path>", {
  r <- parse_error_log(error_lines)[8, ]
  expect_equal(r$ah_code, "AH01276")
  expect_match(r$message_template, "Cannot serve directory <path>", fixed = TRUE)
})

test_that("client IPs never appear in any output column", {
  out <- parse_error_log(error_lines)
  txt <- paste(unlist(lapply(out, as.character)), collapse = " ")
  expect_false(grepl("203\\.0\\.113|198\\.51\\.100|192\\.0\\.2\\.44", txt))
  expect_false(grepl("[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}", txt))
})

test_that("edge cases: empty and NA input", {
  expect_equal(nrow(parse_error_log(character())), 0)
  out <- parse_error_log(c(NA, ""))
  expect_equal(out$parse_ok, c(FALSE, FALSE))
})
