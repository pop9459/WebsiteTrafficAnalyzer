# Cloudflare's published edge ranges (https://www.cloudflare.com/ips/).
# All prefixes are /32 or shorter, which `in_cloudflare()` relies on.
cloudflare_ranges <- c(
  "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
  "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
  "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
  "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
  "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32",
  "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32"
)

#' Check whether addresses belong to Cloudflare's edge network
#'
#' kapsiar.sk sits behind Cloudflare, so requests that come through the proxy
#' are logged with a Cloudflare edge address instead of the visitor's.
#' Requests from other addresses reached the origin server directly, which a
#' normal visitor resolving the domain never does.
#'
#' @param ip Character vector of IPv4 or IPv6 addresses.
#' @param ranges CIDR ranges to test against, each with a prefix of /32 or
#'   shorter.
#' @return Logical vector, `NA` where `ip` is `NA` or not a valid address.
#' @export
in_cloudflare <- function(ip, ranges = cloudflare_ranges) {
  unique_ips <- unique(ip)
  ip_v6 <- grepl(":", unique_ips, fixed = TRUE)
  ip_prefix <- ip_top32(unique_ips)

  range_v6 <- grepl(":", ranges, fixed = TRUE)
  range_prefix <- ip_top32(sub("/.*$", "", ranges))
  range_len <- as.integer(sub("^.*/", "", ranges))

  result <- rep(FALSE, length(unique_ips))
  for (i in seq_along(ranges)) {
    block <- 2^(32 - range_len[i])
    hit <- ip_v6 == range_v6[i] &
      floor(ip_prefix / block) == floor(range_prefix[i] / block)
    result <- result | (hit %in% TRUE)
  }
  result[is.na(ip_prefix)] <- NA
  result[match(ip, unique_ips)]
}

#' The top 32 bits of an IPv4 or IPv6 address as a number
#'
#' For IPv4 that is the whole address; for IPv6 the first two groups.
#' @keywords internal
ip_top32 <- function(ip) {
  out <- rep(NA_real_, length(ip))

  v4 <- !is.na(ip) & grepl("^\\d{1,3}(\\.\\d{1,3}){3}$", ip)
  if (any(v4)) {
    octets <- matrix(as.numeric(unlist(strsplit(ip[v4], ".", fixed = TRUE))), ncol = 4, byrow = TRUE)
    valid <- rowSums(octets > 255) == 0
    out[which(v4)[valid]] <- (octets %*% c(2^24, 2^16, 2^8, 1))[valid]
  }

  v6 <- !is.na(ip) & grepl(":", ip, fixed = TRUE) & grepl("^[0-9A-Fa-f:.]+$", ip)
  if (any(v6)) {
    out[v6] <- vapply(ip[v6], ipv6_top32, numeric(1), USE.NAMES = FALSE)
  }
  out
}

#' @keywords internal
ipv6_top32 <- function(ip) {
  # Groups before "::" are written out; everything after it starts with zeros.
  head <- strsplit(sub("::.*$", "", ip), ":", fixed = TRUE)[[1]]
  values <- strtoi(c(head, "0", "0")[1:2], 16L)
  if (anyNA(values) || any(values > 0xffff)) {
    return(NA_real_)
  }
  values[1] * 2^16 + values[2]
}
