test_that("probe paths are grouped into families", {
  paths <- c(
    "/.env.production", "/api/.env", "/.git/HEAD", "/wp-login.php", "/xmlrpc.php",
    "/.aws/credentials", "/config.json", "/actuator/env", "/backup.sql",
    "/phpmyadmin/", "/cgi-bin/luci", "/SDK/webLanguage", "/info.php",
    "1.1.1.1:80", "http://example.com/",
    "/.gitignore", "/%2egit/%63onfig", "/index.php/feed/atom/",
    "/env", "/.vite/manifest.json", "/dashboard", "/containers/json", "/terraform.tfstate",
    "/id_rsa", "/.vault-token", "/.gitconfig", "/secrets.json", "/_next/static/app.js",
    "/main.js.map", "/%22scripts/main.js%22", "/settings", "/api/config", "/x/randkeyword.PhP7",
    "/", "/index.php", "/phpContent/aboutMe.php", "/scripts/main.js", NA
  )
  expect_equal(probe_family(paths), c(
    "env", "env", "vcs", "wordpress", "wordpress",
    "config_leak", "config_leak", "config_leak", "backup",
    "admin_panel", "device_exploit", "device_exploit", "php_probe",
    "proxy", "proxy",
    "vcs", "vcs", "php_probe",
    "env", "app_probe", "app_probe", "device_exploit", "config_leak",
    "config_leak", "config_leak", "config_leak", "config_leak", "app_probe",
    "app_probe", "app_probe", "app_probe", "app_probe", "php_probe",
    "none", "none", "none", "none", "malformed"
  ))
})

classified <- function() {
  req <- fixture_requests()
  classify_requests(anonymise_requests(req[req$parse_ok, ], "test-salt"))
}

test_that("each fixture request gets the expected class", {
  out <- classified()
  expect_equal(out$client_class, c(
    "human",    # browser through Cloudflare
    "human",    # favicon, same visitor
    "scanner",  # /.env
    "scanner",  # /.git/config
    "bot",      # Googlebot
    "internal", # Apache OPTIONS *
    "scanner",  # malformed request line
    "bot"       # curl
  ))
})

browser_ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

test_that("clients with mostly 4xx responses are scanners", {
  n <- 25
  req <- tibble::tibble(
    ip_hash = "abc",
    via_cloudflare = FALSE,
    time = as.POSIXct("2026-07-10 12:00:00", tz = "UTC") + seq_len(n),
    path = paste0("/page", seq_len(n)),
    status = c(rep(404L, n - 1), 200L),
    user_agent = browser_ua
  )
  expect_true(all(classify_requests(req)$client_class == "scanner"))

  # Behind Cloudflare the address is shared, but one user agent that gets
  # almost only 4xx within an hour is still a scanner.
  req$via_cloudflare <- TRUE
  expect_true(all(classify_requests(req)$client_class == "scanner"))

  # Answered normally and spread over many hours, the requests look like
  # ordinary visitors (a 404 for an unknown path would still be a probe).
  req$time <- as.POSIXct("2026-07-10 00:00:00", tz = "UTC") + 3600 * 2 * seq_len(n)
  req$status <- 200L
  expect_true(all(classify_requests(req)$client_class == "human"))
})

test_that("a browser user agent that floods the site within an hour is a bot", {
  n <- 150
  req <- tibble::tibble(
    ip_hash = paste0("c", seq_len(n)),
    via_cloudflare = TRUE,
    time = as.POSIXct("2026-07-10 06:00:00", tz = "UTC") + seq_len(n),
    path = "/",
    status = 200L,
    user_agent = browser_ua
  )
  expect_true(all(classify_requests(req)$client_class == "bot"))
  expect_true(all(classify_requests(req, burst_requests = 200)$client_class == "human"))
})

test_that("requests for robots.txt and sitemaps are bots even with a browser user agent", {
  req <- tibble::tibble(
    ip_hash = "a",
    via_cloudflare = TRUE,
    time = as.POSIXct("2026-07-10 12:00:00", tz = "UTC") + 0:4,
    path = c("/robots.txt", "/sitemap.xml", "/", "/llms.txt", "/feed/"),
    status = c(404L, 404L, 200L, 404L, 404L),
    user_agent = browser_ua
  )
  expect_equal(classify_requests(req)$client_class, c("bot", "bot", "human", "bot", "bot"))
})

test_that("browsers that bypass Cloudflare stay unknown and tools are scanners", {
  req <- tibble::tibble(
    ip_hash = c("a", "b"),
    via_cloudflare = c(FALSE, TRUE),
    time = as.POSIXct("2026-07-10 12:00:00", tz = "UTC") + 0:1,
    path = c("/", "/"),
    status = c(200L, 200L),
    user_agent = c("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", "feroxbuster/2.13.1")
  )
  expect_equal(classify_requests(req)$client_class, c("unknown", "scanner"))
})

test_that("a 404 for a path the site does not serve is a probe, whatever the user agent", {
  req <- tibble::tibble(
    ip_hash = c("a", "b", "c", "d", "e", "f", "g"),
    via_cloudflare = TRUE,
    time = as.POSIXct("2026-07-10 12:00:00", tz = "UTC") + (0:6) * 4000,
    path = c("/shop", "/feed/atom/", "/privatekey.key", "/favicon.ico", "/robots.txt", "/", "/missing-page"),
    status = c(404L, 404L, 404L, 404L, 404L, 200L, 404L),
    user_agent = c(browser_ua, browser_ua, "Mozilla/5.0 (compatible; GoogleOther)",
                   browser_ua, browser_ua, browser_ua, "curl/8.7.1")
  )
  expect_equal(
    classify_requests(req)$client_class,
    c("scanner", "scanner", "scanner", "human", "bot", "human", "scanner")
  )
})

test_that("a declared crawler is a bot even on probe paths (KAP-55)", {
  req <- tibble::tibble(
    ip_hash = letters[1:7],
    via_cloudflare = TRUE,
    time = as.POSIXct("2026-07-10 12:00:00", tz = "UTC") + (0:6) * 4000,
    path = c("/.env", "/.env", "/.env", "/", "/.git/config", "/missing-page", "/wp-login.php"),
    status = c(404L, 404L, 404L, 200L, 404L, 404L, 404L),
    user_agent = c(
      "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "curl/8.7.1",
      "Mozilla/5.0 (compatible; Nuclei bot)",
      "Mozilla/5.0; GPTBot/1.1; +https://openai.com/gptbot",
      "python-requests/2.31",
      "Mozilla/5.0 (compatible; bingbot/2.0)",
      "Mozilla/5.0 (compatible; ClaudeBot/1.0)"
    )
  )
  expect_equal(
    classify_requests(req)$client_class,
    c("bot", "scanner", "scanner", "bot", "scanner", "bot", "bot")
  )
})

test_that("bot_ua_regex is the union of crawler and generic client patterns", {
  expect_true(grepl(crawler_ua_regex, "googlebot"))
  expect_false(grepl(crawler_ua_regex, "curl/8.7.1"))
  expect_true(grepl(generic_client_ua_regex, "curl/8.7.1"))
  expect_false(grepl(generic_client_ua_regex, "googlebot"))
  expect_true(grepl(bot_ua_regex, "googlebot") && grepl(bot_ua_regex, "wget/1.2"))
})

test_that("the site's section URLs (KAP-112) are real pages, not probes", {
  sections <- c("/about", "/projects/battlebot", "/projects/campus-link/",
                "/portfolio1/presentation", "/portfolio2/pdp", "/traffic.php")
  expect_true(all(is_site_page(sections)))
  expect_equal(probe_family(sections), rep("none", length(sections)))
  expect_false(any(is_site_page(c("/.env", "/admin", "/projects/../etc/passwd", "/wp-login.php"))))
  expect_true(all(is_site_page(c("/", "/index.php", "/phpContent/aboutMe.php"))))
})
