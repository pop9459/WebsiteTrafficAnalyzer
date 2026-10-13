# Paths that really exist on kapsiar.sk. Other PHP paths are probes.
site_php_regex <- "^/(index\\.php|phpcontent/.+\\.php)$"

# Checked in order; the first match wins.
probe_patterns <- c(
  # "CONNECT host:port" or "GET http://host/": testing for an open proxy.
  proxy = "^[^/].*:[0-9]+$|^https?://",
  env = "(^|/)\\.env|^/env$|\\.env$",
  vcs = "(^|/)\\.(git|svn|hg|bzr)(/|$|ignore$|attributes$|modules$)",
  wordpress = "wp-(admin|login|content|includes|config|json)|xmlrpc\\.php|wlwmanifest|(^|/)wordpress(/|$)",
  config_leak = paste0(
    "(^|/)\\.(aws|ssh|docker|vscode|idea|ds_store|ht(access|passwd))|",
    "config\\.(json|js|ya?ml|php|xml|ini)$|credentials|web\\.config|appsettings|",
    "settings\\.py|docker-compose|server-(status|info)|/actuator|storage/logs|",
    "\\.log$|swagger|/graphql|/api-docs|terraform\\.tfstate|",
    "(^|/)\\.(gitconfig|vault-token)|id_(rsa|dsa|ed25519)|secrets?\\.(json|ya?ml)|",
    "(^|/)(env|stats|webpack)\\.json$|database\\.ya?ml"
  ),
  backup = "\\.(sql|bak|old|backup|swp|zip|tar|tgz|rar|7z)$|(^|/)(backup|dump)",
  app_probe = paste0(
    "(^|/)\\.vite/|(^|/)(dist|build)/|(^|/)(_next|_app)/|manifest\\.json$|\\.js\\.map$|",
    "^/(%22|\")|",
    "^/(app|dashboard|account|portal|signin|signup|register|auth|user|settings|manage|my|",
    "profile|workspace|config|api)(/|$)"
  ),
  admin_panel = "phpmyadmin|(^|/)pma(/|$)|adminer|/manager/html|/administrator|(^|/)admin(/|$)|(^|/)login$|/user/login",
  device_exploit = paste0(
    "cgi-bin|boaform|hnap1|goform|/sdk/weblanguage|vendor/phpunit|eval-stdin|",
    "invokefunction|(^|/)solr/|(^|/)console(/|$)|setup\\.cgi|(^|/)(shell|cmd)(\\?|$)|",
    "/containers/json|/_ignition"
  )
)

# Tools that only scan for weaknesses.
scanner_ua_regex <- paste0(
  "feroxbuster|nuclei|zgrab|masscan|nmap|nikto|sqlmap|gobuster|dirbuster|wpscan|",
  "libredtail|crusader|silovik|l9explore|censys|expanse|internet-measurement|",
  "odin|zmap|netcraft|l9scan|leakix|infrawat|palo alto|security research|scan"
)

# Crawlers, previews and generic HTTP clients.
bot_ua_regex <- paste0(
  "bot|crawl|spider|slurp|externalagent|facebookexternalhit|ccbot|claude|",
  "perplexity|bytespider|curl|wget|python|go-http|java/|okhttp|libwww|",
  "httpclient|axios|node-fetch|scrapy|headless|phantom|fetcher|preview|monitor|uptime"
)

browser_ua_regex <- "^mozilla/5\\.0 \\(.*(chrome|firefox|safari|edg)/"

# Files that only crawlers and tools ask for, whatever the user agent says.
crawler_path_regex <- "^/(robots\\.txt|sitemap[^/]*\\.xml|ads\\.txt|llms\\.txt|feed/?$|\\.well-known/)"

#' Map request paths to a probe family
#'
#' Groups paths that scanners request into families, e.g. every `.env`
#' variant becomes `"env"`. Percent-encoded paths (`/%2egit/config`) are
#' decoded first. Paths of the real site, and unknown paths that do not look
#' like a probe, become `"none"`. A missing path (the request line was not
#' valid HTTP) becomes `"malformed"`.
#'
#' @param path Character vector of request paths without query string.
#' @param site_php Regex of PHP paths that really exist on the site; any other
#'   `.php` path is a `"php_probe"`.
#' @return Character vector of families: one of `names(probe_patterns)`,
#'   `"php_probe"`, `"malformed"` or `"none"`.
#' @export
probe_family <- function(path, site_php = site_php_regex) {
  p <- path
  encoded <- !is.na(p) & grepl("%", p, fixed = TRUE)
  p[encoded] <- vapply(p[encoded], function(x) {
    # Malformed escapes (e.g. "%zz") are common in scanner paths: keep the path as is.
    tryCatch(suppressWarnings(utils::URLdecode(x)), error = function(e) x)
  }, character(1), USE.NAMES = FALSE)
  p <- tolower(iconv(p, "UTF-8", "UTF-8", sub = ""))
  family <- rep("none", length(p))
  family[is.na(p)] <- "malformed"

  open <- !is.na(p)
  for (name in names(probe_patterns)) {
    hit <- open & grepl(probe_patterns[[name]], p)
    family[hit] <- name
    open <- open & !hit
  }
  php <- open & grepl("\\.(php[0-9]?|phtml|phar)($|/)", p) & !grepl(site_php, p)
  family[php] <- "php_probe"
  family
}

#' Classify requests as human, bot, scanner, internal or unknown
#'
#' A rule-based classification (KAP-55). Rules, in order:
#'
#' 1. **internal**: Apache's own `OPTIONS *` health checks.
#' 2. **scanner**: the path belongs to a probe family (see [probe_family()]),
#'    the user agent is a known scanning tool, or the client reached the
#'    origin directly and at least `min_requests` of its requests got a 4xx
#'    with a share of at least `min_4xx_share`. The same test is applied to
#'    one user agent within one hour (`min_requests` requests, share of 4xx at
#'    least `min_4xx_share`), which catches scanners that hide behind
#'    Cloudflare and pretend to be a browser.
#' 3. **bot**: a crawler or HTTP-library user agent, no user agent, a request
#'    for `robots.txt`, a sitemap or `.well-known/`, or a user agent that sends
#'    at least `burst_requests` requests within one hour. A real visitor does
#'    not do that on a site this size.
#' 4. **human**: a browser user agent on a request that came through
#'    Cloudflare.
#' 5. **unknown**: everything else, including browser user agents that
#'    reached the origin directly.
#'
#' The per-client 4xx rule only uses direct requests: behind Cloudflare the
#' logged address is a Cloudflare edge server shared by many visitors, which is
#' why the user-agent-hour rules exist.
#'
#' @param requests Output of [anonymise_requests()], parsed rows only.
#' @param min_requests,min_4xx_share Thresholds for the 4xx rules.
#' @param burst_requests Requests of one user agent within one hour from which
#'   the traffic counts as automated.
#' @return `requests` with the extra columns `probe_family` and
#'   `client_class`.
#' @export
classify_requests <- function(requests, min_requests = 20, min_4xx_share = 0.9,
                              burst_requests = 100) {
  requests$probe_family <- probe_family(requests$path)

  clients <- requests |>
    dplyr::filter(!.data$via_cloudflare %in% TRUE) |>
    dplyr::group_by(.data$ip_hash) |>
    dplyr::summarise(
      n = dplyr::n(),
      share_4xx = mean(.data$status >= 400 & .data$status < 500),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$n >= min_requests, .data$share_4xx >= min_4xx_share)

  # One user agent within one hour: a stand-in for "one client" behind Cloudflare.
  cells <- tibble::tibble(
    user_agent = requests$user_agent,
    hour = as.numeric(requests$time) %/% 3600,
    client_error = requests$status >= 400 & requests$status < 500
  ) |>
    dplyr::group_by(.data$user_agent, .data$hour) |>
    dplyr::mutate(n = dplyr::n(), share_4xx = mean(.data$client_error)) |>
    dplyr::ungroup()
  has_ua <- !is.na(requests$user_agent)
  noisy_ua_hour <- has_ua & cells$n >= min_requests & cells$share_4xx >= min_4xx_share
  burst <- has_ua & cells$n >= burst_requests

  ua <- tolower(requests$user_agent)
  noisy_client <- !requests$via_cloudflare %in% TRUE & requests$ip_hash %in% clients$ip_hash

  requests$client_class <- dplyr::case_when(
    grepl("(internal dummy connection)", ua, fixed = TRUE) | requests$path %in% "*" ~ "internal",
    requests$probe_family != "none" ~ "scanner",
    grepl(scanner_ua_regex, ua) ~ "scanner",
    noisy_client ~ "scanner",
    noisy_ua_hour ~ "scanner",
    is.na(ua) | grepl(bot_ua_regex, ua) ~ "bot",
    grepl(crawler_path_regex, tolower(requests$path)) ~ "bot",
    burst ~ "bot",
    grepl(browser_ua_regex, ua) & requests$via_cloudflare %in% TRUE ~ "human",
    .default = "unknown"
  )
  requests
}
