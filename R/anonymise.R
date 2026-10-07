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
#' Derives the fields that need the real IP address first (currently
#' `via_cloudflare`; geo/ASN lookups belong here too), then replaces `ip`
#' with `ip_hash` and drops the `ident`, `user` and `peer_ip` fields.
#'
#' `via_cloudflare` is based on the connecting address: `peer_ip` when the log
#' has it (extended format), otherwise `ip`.
#'
#' @param requests Output of [parse_access_log()].
#' @param salt Secret salt, see [get_salt()].
#' @return `requests` with `ip_hash` and `via_cloudflare` instead of `ip`,
#'   `ident`, `user` and `peer_ip`.
#' @export
anonymise_requests <- function(requests, salt) {
  connecting_ip <- requests$ip
  if ("peer_ip" %in% names(requests)) {
    connecting_ip <- dplyr::coalesce(requests$peer_ip, connecting_ip)
  }
  requests$via_cloudflare <- in_cloudflare(connecting_ip)
  requests$ip_hash <- hash_ip(requests$ip, salt)
  requests$ip <- NULL
  requests$ident <- NULL
  requests$user <- NULL
  requests$peer_ip <- NULL
  dplyr::relocate(requests, "ip_hash", "via_cloudflare")
}
