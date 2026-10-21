# Data quality of the kapsiar.sk access logs (KAP-53).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/data_quality.R
#
# Writes figures 07 and 08 to analysis/figures/ and analysis/data_quality.md.
# Both contain aggregates only (no IPs, user agents or individual paths).

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

invisible(Sys.setlocale("LC_TIME", "C"))

requests <- readRDS("data/processed/requests.rds")
errors <- readRDS("data/processed/errors.rds")
dir.create("analysis/figures", showWarnings = FALSE)

surface <- "#fcfcfb"
blue <- "#2a78d6"
orange <- "#eb6834"

theme_wta <- function() {
  theme_minimal(base_size = 11) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(colour = "#e6e5e1", linewidth = 0.3),
      axis.text = element_text(colour = "#52514e"),
      axis.title = element_text(colour = "#52514e"),
      plot.title = element_text(colour = "#0b0b0b", face = "bold"),
      plot.subtitle = element_text(colour = "#52514e"),
      plot.caption = element_text(colour = "#52514e", hjust = 0),
      legend.position = "top",
      legend.justification = "left",
      legend.title = element_blank(),
      legend.text = element_text(colour = "#52514e")
    )
}

save_fig <- function(plot, name, height = 4.5) {
  ggsave(file.path("analysis/figures", name), plot, width = 8, height = height, dpi = 200, bg = surface)
}

fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
pct <- function(x, d = 1) sprintf("%.*f%%", d, 100 * x)
today <- format(Sys.Date(), "%d %B %Y")

source_caption <- sprintf(
  "Source: kapsiar.sk access log, %s to %s, %s parsed requests.",
  format(min(requests$time), "%d %b"), format(max(requests$time), "%d %b %Y"),
  fmt(nrow(requests))
)

md_table <- function(df) {
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  )
}

n_req <- nrow(requests)

# 1. Coverage ---------------------------------------------------------------
requests$day <- as.Date(requests$time, tz = "UTC")
all_days <- seq(min(requests$day), max(requests$day), by = "day")
daily <- tibble(day = all_days) |>
  left_join(count(requests, day), by = "day") |>
  mutate(n = coalesce(n, 0L))
med_day <- median(daily$n)
q_day <- quantile(daily$n, c(0.25, 0.75))
daily$gap <- daily$n < 0.1 * med_day
gap_days <- daily |> filter(gap)
zero_days <- sum(daily$n == 0)
max_day <- daily |> slice_max(n, n = 1, with_ties = FALSE)

p7 <- ggplot(daily, aes(day, n, fill = gap)) +
  geom_col(width = 1) +
  geom_hline(yintercept = 0.1 * med_day, linetype = "dashed", colour = "#52514e", linewidth = 0.3) +
  scale_fill_manual(values = c(`FALSE` = blue, `TRUE` = orange), labels = c(`FALSE` = "Normal day", `TRUE` = "Gap day (< 10% of median)")) +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.05))) +
  labs(
    title = "Requests per day, with gap days highlighted",
    subtitle = sprintf("Dashed line: 10%% of the daily median (%s requests)", fmt(round(0.1 * med_day))),
    x = NULL, y = "Requests", caption = source_caption
  ) +
  theme_wta()
save_fig(p7, "07_requests_per_day_coverage.png")

# 2. Malformed lines --------------------------------------------------------
n_malformed <- sum(requests$probe_family == "malformed", na.rm = TRUE)
fam <- requests |>
  count(probe_family, sort = TRUE) |>
  mutate(share = n / n_req)
n_parse_not_ok <- sum(!requests$parse_ok)

# 3. Missingness ------------------------------------------------------------
fields <- c("method", "path", "protocol", "status", "bytes", "referer", "user_agent", "bytes_in", "bytes_out", "duration_us")
miss <- bind_rows(lapply(fields, function(f) {
  v <- requests[[f]]
  na <- is.na(v)
  dash <- if (is.character(v)) !na & (v == "-" | v == "") else rep(FALSE, length(v))
  tibble(field = f, n_na = sum(na), n_dash = sum(dash), n_missing = sum(na | dash), share = mean(na | dash))
}))
miss$structural <- miss$field %in% c("bytes_in", "bytes_out", "duration_us")

p8 <- ggplot(miss, aes(share, reorder(field, share), fill = structural)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = pct(share)), hjust = -0.1, colour = "#52514e", size = 3.2) +
  scale_fill_manual(values = c(`FALSE` = blue, `TRUE` = orange), labels = c(`FALSE` = "Field in all log formats", `TRUE` = "Only in extended format")) +
  scale_x_continuous(labels = scales::label_percent(), limits = c(0, 1.12), expand = expansion(c(0, 0))) +
  labs(
    title = "Share of missing values per field",
    subtitle = "NA or '-' counts as missing",
    x = "Share of requests", y = NULL, caption = source_caption
  ) +
  theme_wta() +
  theme(panel.grid.major.x = element_line(colour = "#e6e5e1", linewidth = 0.3), panel.grid.major.y = element_blank())
save_fig(p8, "08_missingness_per_field.png", height = 4)

# 4. Duplicates and clock ---------------------------------------------------
key <- paste(requests$ip_hash, as.numeric(requests$time), requests$request, requests$status, requests$bytes, sep = "\r")
dup <- duplicated(key)
n_dup_extra <- sum(dup)
n_dup_groups <- length(unique(key[dup]))
n_in_dup_groups <- sum(key %in% unique(key[dup]))
dup_family <- requests[key %in% unique(key[dup]), ] |> count(probe_family, sort = TRUE)

tz_time <- attr(requests$time, "tzone")
tz_received <- attr(requests$received, "tzone")
has_received <- !all(is.na(requests$received))
off <- as.numeric(difftime(requests$received, requests$time, units = "secs"))
off_ok <- off[!is.na(off)]
off_q <- quantile(off_ok, c(0.5, 0.99))
off_stats <- c(
  min = min(off_ok), median = off_q[[1]], p99 = off_q[[2]], max = max(off_ok),
  neg = sum(off_ok < 0), over60 = sum(abs(off_ok) > 60)
)
n_time_na <- sum(is.na(requests$time))
time_sorted <- !is.unsorted(requests$time, na.rm = TRUE)

# 5. Cloudflare -------------------------------------------------------------
cf_share <- mean(requests$via_cloudflare, na.rm = TRUE)
cf_na <- sum(is.na(requests$via_cloudflare))
n_ips <- n_distinct(requests$ip_hash)

# 6. Error log --------------------------------------------------------------
errors$day <- as.Date(errors$time, tz = "UTC")
err_daily <- count(errors, day)
err_all <- tibble(day = seq(min(errors$day), max(errors$day), by = "day")) |>
  left_join(err_daily, by = "day") |>
  mutate(n = coalesce(n, 0L))
err_q <- quantile(err_all$n, c(0.25, 0.75))
err_max <- err_all |> slice_max(n, n = 1, with_ties = FALSE)

# Write the report ----------------------------------------------------------
gap_txt <- if (nrow(gap_days) == 0) {
  "No day falls below 10% of the median."
} else {
  sprintf(
    "%d day(s) fall below 10%% of the median: %s.",
    nrow(gap_days),
    paste(sprintf("%s (%s requests)", format(gap_days$day, "%d %b"), fmt(gap_days$n)), collapse = ", ")
  )
}
low_days <- daily |> filter(n < 0.5 * med_day, !gap)

lines <- c(
  "# Data quality: kapsiar.sk access logs",
  "",
  sprintf("Generated by `analysis/data_quality.R` on %s. Aggregates only.", today),
  "",
  sprintf(
    "Dataset: `data/processed/requests.rds` (%s parsed requests) and `data/processed/errors.rds` (%s error-log lines). Client IPs are replaced by a hash (`ip_hash`) during import.",
    fmt(n_req), fmt(nrow(errors))
  ),
  "",
  "## 1. Coverage",
  "",
  sprintf(
    "The requests span %s to %s (UTC), a calendar range of %d days. %d of these days have zero requests. %s",
    format(min(requests$time), "%d %B %Y"), format(max(requests$time), "%d %B %Y"), length(all_days), zero_days, gap_txt
  ),
  "",
  sprintf(
    "Requests per day: median %s, interquartile range %s to %s, maximum %s (on %s). A further %d day(s) lie between 10%% and 50%% of the median.",
    fmt(round(med_day)), fmt(round(q_day[[1]])), fmt(round(q_day[[2]])), fmt(max_day$n), format(max_day$day, "%d %b %Y"), nrow(low_days)
  ),
  "",
  "The first and last day of the range are usually partial (container created or log fetched during the day), so they can appear as low days without being outages.",
  "",
  "![Requests per day, gap days highlighted](figures/07_requests_per_day_coverage.png)",
  "",
  "*Figure 7. Requests per day. Orange bars are gap days (fewer than 10% of the median daily count); the dashed line marks that threshold.*",
  "",
  "## 2. Malformed and unparsable lines",
  "",
  sprintf(
    "`requests.rds` only holds rows that the access-log parser accepted (rows with `parse_ok == FALSE`: %d). Log lines that did not match the Apache format at all were dropped during import. Their count is not stored in the processed data, so it is a limitation of this report; `data-raw/import_logs.R` prints it at import time.",
    n_parse_not_ok
  ),
  "",
  sprintf(
    "Requests whose request line was not valid HTTP (`probe_family == \"malformed\"`) are kept: %s requests, %s of all parsed requests. They carry no method or path.",
    fmt(n_malformed), pct(n_malformed / n_req, 2)
  ),
  "",
  "Requests by probe family (families, not individual paths):",
  "",
  md_table(fam |> transmute(`Probe family` = ifelse(is.na(probe_family), "(none)", probe_family), Requests = fmt(n), Share = pct(share))),
  "",
  "## 3. Missingness per field",
  "",
  "A value counts as missing if it is `NA` or the Apache placeholder `-` (or an empty string).",
  "",
  md_table(miss |> transmute(
    Field = field, `NA` = fmt(n_na), `'-' or empty` = fmt(n_dash),
    `Missing` = fmt(n_missing), Share = pct(share, 2),
    Type = ifelse(structural, "structural", "incidental")
  )),
  "",
  "![Missingness per field](figures/08_missingness_per_field.png)",
  "",
  "*Figure 8. Share of missing values per field. Orange bars mark fields that exist only in the extended log format.*",
  "",
  "`bytes_in`, `bytes_out` and `duration_us` are structurally missing. They come from the `%I %O %D` directives of the extended log format, which the server uses only from 7 October 2026. This dataset ends before that date, so these fields are 100% missing by design and not a data error. `method` and `path` are missing exactly for the malformed request lines (section 2); `protocol` is missing for those plus a handful of other rows with an incomplete request line. `referer` and `user_agent` are `NA` where the client sent `-` (the parser converts the Apache placeholder to `NA`), so a missing referer (about 98%) mostly means direct or script traffic, and a missing user agent (about 13%) means the client sent none. `status` and `bytes` are always present (responses without a body are logged with 0 bytes, 420 rows here).",
  "",
  "## 4. Duplicates and clock",
  "",
  sprintf(
    "Exact duplicates (same `ip_hash`, `time`, `request`, `status` and `bytes`): %s surplus rows (%s of requests), in %s distinct duplicated keys covering %s rows in total. Apache logs time at one-second resolution, so a duplicate can be a genuine repeated request within the same second (for example a client fetching the same resource twice) rather than a logging error. The rows are kept in the data.",
    fmt(n_dup_extra), pct(n_dup_extra / n_req, 3), fmt(n_dup_groups), fmt(n_in_dup_groups)
  ),
  "",
  if (nrow(dup_family) > 0) {
    c(
      "Duplicated rows by probe family:", "",
      md_table(dup_family |> transmute(`Probe family` = ifelse(is.na(probe_family), "(none)", probe_family), Rows = fmt(n))), ""
    )
  },
  sprintf(
    "Timezone: `time` carries the tzone attribute `%s`%s, so all timestamps are UTC. Missing timestamps: %d. Rows are %sstored in timestamp order (Apache writes the time when a request starts, so lines of slow requests can appear after later ones).",
    ifelse(is.null(tz_time), "(none)", tz_time),
    ifelse(is.null(tz_received) || !has_received, "", sprintf(", `received` carries `%s`", tz_received)),
    n_time_na, ifelse(time_sorted, "", "not ")
  ),
  "",
  if (length(off_ok) > 0) {
    sprintf(
      "`received` is the time Docker received the line; `time` is the time Apache logged for the request. The difference `received - time` (seconds) over %s rows: minimum %.1f, median %.1f, 99th percentile %.1f, maximum %.1f. %s rows are negative and %s rows differ by more than 60 seconds.",
      fmt(length(off_ok)), off_stats[["min"]], off_stats[["median"]], off_stats[["p99"]], off_stats[["max"]], fmt(off_stats[["neg"]]), fmt(off_stats[["over60"]])
    )
  } else {
    "`received` is empty for all rows, so no clock comparison is possible."
  },
  "",
  "## 5. Known blind spots",
  "",
  sprintf("- **No incoming bytes.** `bytes_in` is absent before the format change on 7 October 2026, so request sizes and upload volume cannot be analysed (this limits KAP-54)."),
  sprintf(
    "- **Cloudflare.** %s of requests (%s of %s) carry a Cloudflare edge address instead of the visitor's (`via_cloudflare == TRUE`; %d rows undetermined). Per-client statistics, such as requests per IP, are only valid for the remaining direct-to-origin traffic (%s distinct hashed addresses overall, mixing both kinds).",
    pct(cf_share), fmt(sum(requests$via_cloudflare, na.rm = TRUE)), fmt(n_req), cf_na, fmt(n_ips)
  ),
  sprintf("- **Start of the data.** Nothing exists before the web container was created on 9 July 2026. The first request in the dataset is on %s.", format(min(requests$time), "%d %B %Y")),
  "- **Historical logs.** Logs from June 2025 to May 2026 exist only in a local-only backup and are not part of this dataset (KAP-104).",
  "- **Dropped lines.** The count of unparsable log lines is not preserved (section 2).",
  "- **Server-side only.** The logs show requests, not people: there is no session or user identifier, and user agents can be forged.",
  "",
  "## 6. Error log",
  "",
  sprintf(
    "`errors.rds` holds %s lines (Apache error log, stderr) from %s to %s. Lines per day over the %d calendar days in that range: median %s, interquartile range %s to %s, maximum %s (on %s). Only the volume is described here; the content of the error log is analysed separately (KAP-71).",
    fmt(nrow(errors)), format(min(errors$day), "%d %b %Y"), format(max(errors$day), "%d %b %Y"), nrow(err_all),
    fmt(round(median(err_all$n))), fmt(round(err_q[[1]])), fmt(round(err_q[[2]])), fmt(err_max$n), format(err_max$day, "%d %b %Y")
  ),
  "",
  "## Implications for the analysis",
  "",
  sprintf("- Daily trends are reliable over the covered range; treat the %d gap day(s) and the partial first and last day as missing data, not as zero traffic.", nrow(gap_days)),
  "- Do not use `bytes_in`, `bytes_out` or `duration_us`; use `bytes` (outgoing body bytes) for volume.",
  sprintf("- Per-client statistics (requests per IP, session-like features) hold only for direct traffic; %s of requests come via Cloudflare and need a separate treatment until `CF-Connecting-IP` is logged.", pct(cf_share, 0)),
  "- Keep malformed requests as their own probe family instead of dropping them; they have no method, path or protocol.",
  "- Exact duplicates are plausible same-second repeats, so they are not removed.",
  "- Conclusions cover 9 July 2026 onwards only; earlier history needs the local backup (KAP-104).",
  ""
)
writeLines(unlist(lines), "analysis/data_quality.md")
message("Wrote analysis/data_quality.md and figures 07, 08")
