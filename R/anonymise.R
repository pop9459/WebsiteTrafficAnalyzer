#' Get the secret salt used to hash IP addresses
#'
#' The salt is read from the `WTA_SALT` environment variable, or else from
#' `~/.config/websitetrafficanalyzer/salt`. It must never be stored in the
#' repository: anyone with the salt can test guesses against the hashes.
#'
#' @param create If `TRUE` and no salt exists yet, generate a random one and
#'   write it to the salt file (readable only by the owner).
#' @param path Location of the salt file.
#' @return The salt as a single string.
#' @export
get_salt <- function(create = FALSE,
                     path = file.path(Sys.getenv("HOME"), ".config", "websitetrafficanalyzer", "salt")) {
  salt <- Sys.getenv("WTA_SALT")
  if (nzchar(salt)) {
    return(salt)
  }

  if (!file.exists(path) && create) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    bytes <- openssl::rand_bytes(32)
    writeLines(paste(format(bytes), collapse = ""), path)
    Sys.chmod(path, "0600")
  }

  if (!file.exists(path)) {
    rlang::abort(c(
      "No salt found for IP hashing.",
      i = "Set the WTA_SALT environment variable, or call `get_salt(create = TRUE)`."
    ))
  }

  salt <- trimws(readLines(path, n = 1, warn = FALSE))
  if (!nzchar(salt)) {
    rlang::abort(paste0("Salt file '", path, "' is empty."))
  }
  salt
}

#' Hash IP addresses with a salted HMAC
#'
#' Each address becomes the first 16 hex characters of
#' HMAC-SHA256(salt, ip). The same IP and salt always give the same hash, so
#' requests can still be grouped per client without storing the address.
#'
#' @param ip Character vector of IP addresses.
#' @param salt Secret salt, see [get_salt()].
#' @return Character vector of hashes, `NA` where `ip` is `NA`.
#' @export
hash_ip <- function(ip, salt) {
  if (!is.character(salt) || length(salt) != 1 || !nzchar(salt)) {
    rlang::abort("`salt` must be a single non-empty string.")
  }
  # Hash each distinct address once: there are far fewer clients than requests.
  unique_ips <- unique(ip[!is.na(ip)])
  hashes <- vapply(
    unique_ips,
    function(x) substr(digest::hmac(salt, x, algo = "sha256"), 1, 16),
    character(1),
    USE.NAMES = FALSE
  )
  hashes[match(ip, unique_ips)]
}

#' Anonymise parsed requests
#'
#' Derives the fields that need the real IP address first (`via_cloudflare`,
#' and `country`, `asn` and `as_org` from [geo_lookup()]), then replaces `ip`
#' with `ip_hash` and drops the `ident`, `user` and `peer_ip` fields.
#'
#' `via_cloudflare` is based on the connecting address: `peer_ip` when the log
#' has it (extended format), otherwise `ip`.
#'
#' Geo fields describe the logged client address `ip`. Since the extended log
#' format (7 Oct 2026) that is the visitor's own address even for requests via
#' Cloudflare (`peer_ip` is the edge). When `ip` itself is a Cloudflare edge
#' server (old format, proxied request), the geo fields are `NA`: the edge's
#' country and ASN say nothing about the visitor. They are also `NA` when no database is
#' available (a message is shown once), so tests and CI work without one.
#'
#' @param requests Output of [parse_access_log()].
#' @param salt Secret salt, see [get_salt()].
#' @param geo_db Database from [load_geo_db()]. The default loads (and caches)
#'   the one in [geo_dir()], or uses `NA` geo fields if there is none.
#' @return `requests` with `ip_hash`, `via_cloudflare`, `country`, `asn` and
#'   `as_org` instead of `ip`, `ident`, `user` and `peer_ip`.
#' @export
anonymise_requests <- function(requests, salt, geo_db = default_geo_db()) {
  connecting_ip <- requests$ip
  if ("peer_ip" %in% names(requests)) {
    connecting_ip <- dplyr::coalesce(requests$peer_ip, connecting_ip)
  }
  requests$via_cloudflare <- in_cloudflare(connecting_ip)
  if (is.null(geo_db)) {
    geo <- tibble::tibble(country = rep(NA_character_, nrow(requests)),
                          asn = NA_integer_, as_org = NA_character_)
  } else {
    # Look up the logged client address (`ip`). In the extended format that is
    # the visitor even behind Cloudflare; in the old format it is the edge.
    lookup_ip <- requests$ip
    lookup_ip[in_cloudflare(lookup_ip) %in% TRUE] <- NA
    geo <- geo_lookup(lookup_ip, geo_db)
  }
  requests$country <- geo$country
  requests$asn <- geo$asn
  requests$as_org <- geo$as_org
  requests$ip_hash <- hash_ip(requests$ip, salt)
  requests$ip <- NULL
  requests$ident <- NULL
  requests$user <- NULL
  requests$peer_ip <- NULL
  dplyr::relocate(requests, "ip_hash", "via_cloudflare", "country", "asn", "as_org")
}
