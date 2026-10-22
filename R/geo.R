# Country and ASN lookup from the DB-IP Lite CSV databases.
# IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0.

geo_attribution <- "IP Geolocation by DB-IP (https://db-ip.com)"

#' Directory with the DB-IP Lite databases
#'
#' The `WTA_GEO_DIR` environment variable, or else
#' `~/.local/share/websitetrafficanalyzer/geo`. The databases live outside
#' the repository.
#'
#' @return A path.
#' @export
geo_dir <- function() {
  dir <- Sys.getenv("WTA_GEO_DIR")
  if (nzchar(dir)) {
    return(dir)
  }
  file.path(Sys.getenv("HOME"), ".local", "share", "websitetrafficanalyzer", "geo")
}

#' Load the DB-IP Lite country and ASN databases
#'
#' Reads the CSV variants (`dbip-country-lite-*.csv[.gz]` and
#' `dbip-asn-lite-*.csv[.gz]`, newest file wins) into sorted range tables for
#' [geo_lookup()]. Data: IP Geolocation by DB-IP (<https://db-ip.com>),
#' licensed CC BY 4.0, so published results must carry that attribution.
#'
#' IPv4 ranges are stored exactly. IPv6 ranges are stored by their top 48
#' bits (exact as a double), which is exact for every range of /48 or
#' shorter; the databases contain no longer prefixes of practical relevance.
#'
#' @param dir Directory with the CSV files, see [geo_dir()].
#' @return A `wta_geo_db` object for [geo_lookup()].
#' @export
load_geo_db <- function(dir = geo_dir()) {
  find_db <- function(kind) {
    files <- sort(list.files(dir, pattern = paste0("^dbip-", kind, "-lite.*\\.csv(\\.gz)?$"),
                             full.names = TRUE), decreasing = TRUE)
    if (!length(files)) {
      rlang::abort(c(
        paste0("No DB-IP ", kind, " database found in '", dir, "'."),
        i = "Download dbip-country-lite and dbip-asn-lite CSVs from https://db-ip.com/db/lite.php into `geo_dir()`."
      ))
    }
    files[1]
  }
  read_db <- function(path, value_cols) {
    raw <- readr::read_csv(
      path, col_names = c("start", "end", value_cols),
      col_types = readr::cols(.default = "c"), progress = FALSE
    )
    v6 <- grepl(":", raw$start, fixed = TRUE)
    make <- function(rows, key) {
      tbl <- rows[c(value_cols)]
      tbl$from <- key(rows$start)
      tbl$to <- key(rows$end)
      tbl[order(tbl$from), ]
    }
    list(v4 = make(raw[!v6, ], ip_key4), v6 = make(raw[v6, ], ip_key6))
  }
  country <- read_db(find_db("country"), "country")
  asn <- read_db(find_db("asn"), c("asn", "as_org"))
  for (v in c("v4", "v6")) {
    asn[[v]]$asn <- as.integer(asn[[v]]$asn)
  }
  structure(list(country = country, asn = asn), class = "wta_geo_db")
}

#' Look up country and ASN for IP addresses
#'
#' Vectorised with [findInterval()] over the sorted range starts. Addresses
#' outside every range, invalid addresses and `NA` give `NA`.
#'
#' @param ip Character vector of IPv4 or IPv6 addresses.
#' @param db Database from [load_geo_db()].
#' @return A tibble with `country` (ISO 3166 code), `asn` (integer) and
#'   `as_org` (organisation name), one row per element of `ip`.
#' @export
geo_lookup <- function(ip, db) {
  unique_ips <- unique(ip)
  v6 <- !is.na(unique_ips) & grepl(":", unique_ips, fixed = TRUE)
  key <- rep(NA_real_, length(unique_ips))
  key[!v6] <- ip_key4(unique_ips[!v6])
  key[v6] <- ip_key6(unique_ips[v6])

  find <- function(part, column) {
    out <- rep(NA, length(unique_ips))
    for (is_v6 in c(FALSE, TRUE)) {
      table <- part[[if (is_v6) "v6" else "v4"]]
      rows <- which(v6 == is_v6 & !is.na(key))
      if (!length(rows) || !nrow(table)) next
      idx <- findInterval(key[rows], table$from)
      hit <- idx > 0
      hit[hit] <- key[rows][hit] <= table$to[idx[hit]]
      out[rows[hit]] <- table[[column]][idx[hit]]
    }
    out
  }

  at <- match(ip, unique_ips)
  tibble::tibble(
    country = as.character(find(db$country, "country"))[at],
    asn = as.integer(find(db$asn, "asn"))[at],
    as_org = as.character(find(db$asn, "as_org"))[at]
  )
}

#' Numeric key of IPv4 addresses (NA when not a valid IPv4 address)
#' @keywords internal
ip_key4 <- function(ip) {
  out <- rep(NA_real_, length(ip))
  ok <- !is.na(ip) & grepl("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", ip)
  if (any(ok)) {
    octets <- matrix(as.numeric(unlist(strsplit(ip[ok], ".", fixed = TRUE))), ncol = 4, byrow = TRUE)
    value <- as.vector(octets %*% c(2^24, 2^16, 2^8, 1))
    value[rowSums(octets > 255) > 0] <- NA
    out[ok] <- value
  }
  out
}

#' Numeric key of IPv6 addresses: the top 48 bits (NA when invalid)
#' @keywords internal
ip_key6 <- function(ip) {
  out <- rep(NA_real_, length(ip))
  ok <- !is.na(ip) & grepl("^[0-9A-Fa-f:]+$", ip) & grepl(":", ip, fixed = TRUE)
  if (any(ok)) {
    x <- ip[ok]
    # Groups before "::" are written out, what follows starts with zeros.
    head <- ifelse(grepl("::", x, fixed = TRUE), sub("::.*$", "", x), x)
    padded <- paste0(head, ":0:0:0")
    group <- function(i) {
      g <- sub("^([^:]*):([^:]*):([^:]*):.*$", paste0("\\", i), padded)
      g[g == ""] <- "0"
      as.numeric(strtoi(g, 16L))
    }
    out[ok] <- group(1) * 2^32 + group(2) * 2^16 + group(3)
  }
  out
}

# Session cache so repeated anonymise_requests() calls (e.g. per chunk) load
# the databases once.
geo_state <- new.env(parent = emptyenv())

#' @keywords internal
geo_cache_clear <- function() {
  rm(list = ls(geo_state), envir = geo_state)
  invisible(NULL)
}

#' The default database for anonymise_requests(): cached, or NULL if missing
#' @keywords internal
default_geo_db <- function() {
  dir <- geo_dir()
  if (!is.null(geo_state$db) && identical(geo_state$dir, dir)) {
    return(geo_state$db)
  }
  if (identical(geo_state$missing_dir, dir)) {
    return(NULL)
  }
  db <- tryCatch(load_geo_db(dir), error = function(e) NULL)
  if (is.null(db)) {
    geo_state$missing_dir <- dir
    rlang::inform("No DB-IP databases found in the geo directory: country, asn and as_org will be NA.")
  } else {
    geo_state$db <- db
    geo_state$dir <- dir
  }
  db
}
