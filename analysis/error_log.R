# Apache/PHP error-log analysis (KAP-71).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/error_log.R
#
# Writes analysis/figures/09_errors_vs_scanner_requests.png and
# analysis/error_log_summary.md. Both contain aggregates only: client IPs are
# dropped by parse_error_log() and message templates are IPv4-masked.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  devtools::load_all(quiet = TRUE)
})

invisible(Sys.setlocale("LC_TIME", "C"))

requests <- readRDS("data/processed/requests.rds")
errors_raw <- readRDS("data/processed/errors.rds")
dir.create("analysis/figures", showWarnings = FALSE)

surface <- "#fcfcfb"
scanner_colour <- "#1baf7a"
error_colour <- "#eb6834"

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

mask_ip <- function(x) gsub("\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b", "<ip>", x)
md_escape <- function(x) gsub("|", "\\|", x, fixed = TRUE)
md_table <- function(df) {
  df[] <- lapply(df, function(col) if (is.numeric(col)) fmt(col) else md_escape(as.character(col)))
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  )
}
fmt <- function(x) format(x, big.mark = ",", trim = TRUE)

parsed <- parse_error_log(errors_raw$line)
# Prefer the timestamp inside the line; fall back to the Docker timestamp.
parsed$time <- dplyr::coalesce(parsed$time, errors_raw$time)
rm(errors_raw)
parsed <- parsed |> mutate(message_template = gsub("`", "'", mask_ip(message_template), fixed = TRUE))

n_total <- nrow(parsed)
n_ok <- sum(parsed$parse_ok)
parse_rate <- n_ok / n_total

# Lines per day ---------------------------------------------------------------
daily <- parsed |> count(day = as.Date(time))
daily_summary <- tibble::tibble(
  Statistic = c("Days with errors", "Mean", "Median", "Max", "Busiest day"),
  Value = c(
    nrow(daily), fmt(round(mean(daily$n))), fmt(median(daily$n)), fmt(max(daily$n)),
    paste0(daily$day[which.max(daily$n)], " (", fmt(max(daily$n)), ")")
  )
)

by_module <- parsed |> count(module = coalesce(module, "(none)"), sort = TRUE) |> mutate(share = sprintf("%.1f%%", 100 * n / n_total))
by_level <- parsed |> count(level = coalesce(level, "(none)"), sort = TRUE) |> mutate(share = sprintf("%.1f%%", 100 * n / n_total))
by_module_level <- parsed |> count(module = coalesce(module, "(none)"), level = coalesce(level, "(none)"), sort = TRUE)
php_types <- parsed |> filter(!is.na(php_error_type)) |> count(php_error_type, sort = TRUE)

templates <- parsed |>
  filter(parse_ok) |>
  count(message_template, sort = TRUE)
top_templates <- templates |> filter(n >= 5) |> slice_head(n = 15) |>
  mutate(share = sprintf("%.1f%%", 100 * n / n_total))

# Join with scanner requests per hour -----------------------------------------
hour_of <- function(x) as.POSIXct(format(x, "%Y-%m-%d %H:00:00"), tz = "UTC")
attr(requests$time, "tzone") <- "UTC"
attr(parsed$time, "tzone") <- "UTC"
hourly_req <- requests |>
  filter(client_class == "scanner") |>
  count(hour = hour_of(time), name = "scanner_requests")
hourly_err <- parsed |> filter(!is.na(time)) |> count(hour = hour_of(time), name = "error_lines")
span <- seq(min(hourly_req$hour, hourly_err$hour), max(hourly_req$hour, hourly_err$hour), by = "hour")
# Restrict to hours where the access log has any request, so gaps in the log
# are not counted as "zero scanner requests".
active_hours <- unique(hour_of(requests$time))
hourly <- tibble::tibble(hour = span) |>
  filter(hour %in% active_hours) |>
  left_join(hourly_req, by = "hour") |>
  left_join(hourly_err, by = "hour") |>
  mutate(across(c(scanner_requests, error_lines), \(x) coalesce(x, 0L)))
rho <- cor(hourly$scanner_requests, hourly$error_lines, method = "spearman")
rho_nonzero <- hourly |> filter(scanner_requests > 0 | error_lines > 0)
rho_active <- cor(rho_nonzero$scanner_requests, rho_nonzero$error_lines, method = "spearman")

source_caption <- sprintf(
  "Source: kapsiar.sk error and access logs, %s to %s. %s hours, Spearman rho = %.2f.",
  format(min(hourly$hour), "%d %b"), format(max(hourly$hour), "%d %b %Y"), fmt(nrow(hourly)), rho
)
p <- ggplot(hourly, aes(scanner_requests, error_lines)) +
  geom_point(alpha = 0.35, size = 1.4, colour = error_colour) +
  scale_x_continuous(trans = "pseudo_log", breaks = c(0, 10, 100, 1000, 10000), labels = scales::label_comma()) +
  scale_y_continuous(trans = "pseudo_log", breaks = c(0, 10, 100, 1000), labels = scales::label_comma()) +
  labs(
    title = "Error-log volume follows scanner traffic",
    subtitle = "One point per hour; log scales",
    x = "Scanner requests in the hour", y = "Error-log lines in the hour", caption = source_caption
  ) +
  theme_wta() +
  theme(panel.grid.major.x = element_line(colour = "#e6e5e1", linewidth = 0.3))
ggsave("analysis/figures/09_errors_vs_scanner_requests.png", p, width = 8, height = 4.5, dpi = 200, bg = surface)

# Real site bugs ----------------------------------------------------------------
site_re <- "/var/www/html/(index\\.php|phpContent/)"
site_bugs <- templates |> filter(grepl(site_re, message_template))
php_internal <- parsed |> filter(!is.na(php_error_type), parse_ok)

# Write summary ---------------------------------------------------------------
date_range <- range(parsed$time, na.rm = TRUE)
out <- c(
  "# Error-log summary (KAP-71)",
  "",
  "Generated by `analysis/error_log.R`. Aggregates only: client addresses are dropped by `parse_error_log()` and templates are IPv4-masked.",
  "",
  "## Overview",
  "",
  sprintf("- Error lines: %s, from %s to %s (UTC).", fmt(n_total), format(date_range[1], "%Y-%m-%d"), format(date_range[2], "%Y-%m-%d")),
  sprintf("- Parse rate: %s of %s lines (%.2f%%). Unparsed: %s.", fmt(n_ok), fmt(n_total), 100 * parse_rate, fmt(n_total - n_ok)),
  sprintf("- Distinct message templates: %s.", fmt(nrow(templates))),
  "",
  "## Lines per day",
  "",
  md_table(daily_summary),
  "",
  "## By module and level",
  "",
  md_table(by_module |> rename(Module = module, Lines = n, Share = share)),
  "",
  md_table(by_level |> rename(Level = level, Lines = n, Share = share)),
  "",
  md_table(by_module_level |> rename(Module = module, Level = level, Lines = n)),
  "",
  "## PHP error types",
  "",
  if (nrow(php_types) > 0) {
    md_table(php_types |> rename(`PHP error type` = php_error_type, Lines = n))
  } else {
    sprintf("No line carries a `PHP <type>:` prefix. All %s `php` module lines are \"script not found\" errors, which Apache's mod_php emits without a type.", fmt(sum(parsed$module == "php", na.rm = TRUE)))
  },
  "",
  "## Top message templates (>= 5 occurrences)",
  "",
  md_table(top_templates |> mutate(message_template = paste0("`", message_template, "`")) |>
    rename(Template = message_template, Lines = n, Share = share)),
  "",
  "## Errors vs. scanner requests (per hour)",
  "",
  sprintf("- Hours compared: %s (hours with at least one access-log request).", fmt(nrow(hourly))),
  sprintf("- Spearman correlation, all hours: **%.2f**.", rho),
  sprintf("- Spearman correlation, only hours with scanner requests or error lines: %.2f (%s hours).", rho_active, fmt(nrow(rho_nonzero))),
  sprintf("- Hours with error lines: %s; hours with scanner requests: %s.", fmt(sum(hourly$error_lines > 0)), fmt(sum(hourly$scanner_requests > 0))),
  "",
  "![Error lines vs scanner requests per hour](figures/09_errors_vs_scanner_requests.png)",
  "",
  "## Real site bugs",
  "",
  if (nrow(site_bugs) > 0) {
    c(
      "Templates that point at the site's own code (`/var/www/html/index.php` or `phpContent/`):",
      "",
      md_table(site_bugs |> mutate(message_template = paste0("`", message_template, "`")) |>
        rename(Template = message_template, Lines = n))
    )
  } else {
    c(
      "No error template points at the site's own files (`/var/www/html/index.php`, `phpContent/`). No PHP warnings, notices or fatal errors from the site's code appear in the log.",
      sprintf("The only PHP-related errors are `script ... not found or unable to stat` (%s lines): requests for PHP files that do not exist, i.e. probes, not bugs in the site.", fmt(sum(grepl("^script <s> not found", parsed$message_template), na.rm = TRUE)))
    )
  },
  "",
  "## Implications",
  "",
  sprintf("- The error log is almost entirely scanner noise: %s of the lines are PHP \"script not found\", denied-by-config, invalid-URI or directory-listing errors triggered by probes.",
    sprintf("%.2f%%", 100 * mean(grepl("^script <s> not found|client denied|invalid URI|Cannot serve directory", parsed$message_template)))),
  "- Error-line volume can serve as a second, independent scanner signal next to the path-based `probe_family()` rules. Hours where scanners hit PHP files show up as `script not found` bursts.",
  "- `mpm_prefork` `MaxRequestWorkers` errors (a handful of lines) show scanner floods can exhaust Apache workers; worth watching if bursts grow.",
  "- The summary drops client addresses, so errors cannot be attributed per client; use the access log for that.",
  "- Because errors from probes dominate, alerting on raw error counts is useless; alert on new templates or on `php` warnings from the site's own files instead.",
  ""
)
writeLines(out, "analysis/error_log_summary.md")
cat("Wrote analysis/error_log_summary.md and figure 09\n")
