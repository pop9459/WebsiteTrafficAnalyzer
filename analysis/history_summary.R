# Summary of the historical Docker logs (KAP-104, input for KAP-54).
#
# Usage (from the repo root, after data-raw/import_history.R):
#   Rscript analysis/history_summary.R [--in DIR]
# Default --in data/processed/history (the per-file .rds aggregates).
#
# Writes analysis/history_summary.md and figures 10 and 11. The input holds
# aggregates only (per day: class, status, probe family, client counts), so
# everything written here is an aggregate too. A file counts as the web
# container when at least half of its stdout lines parse as Apache requests.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
invisible(Sys.setlocale("LC_TIME", "C"))

args <- commandArgs(trailingOnly = TRUE)
in_dir <- if ("--in" %in% args) args[[match("--in", args) + 1]] else "data/processed/history"
files <- list.files(in_dir, pattern = "\\.rds$", full.names = TRUE)
if (!length(files)) stop("No .rds files in ", in_dir, "; run data-raw/import_history.R first.")
dir.create("analysis/figures", recursive = TRUE, showWarnings = FALSE)

class_levels <- c("human", "bot", "scanner", "unknown", "internal")
class_colours <- c(human = "#2a78d6", bot = "#eb6834", scanner = "#1baf7a", unknown = "#eda100", internal = "#e87ba4")
surface <- "#fcfcfb"
theme_wta <- function() {
  theme_minimal(base_size = 11) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(colour = "#e6e5e1", linewidth = 0.3),
      plot.title = element_text(face = "bold"),
      legend.position = "top", legend.justification = "left", legend.title = element_blank()
    )
}
fmt <- function(x, digits = 0) format(round(x, digits), big.mark = ",", nsmall = digits, scientific = FALSE)
gb <- function(x) x / 1e9
md_table <- function(df) {
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  )
}

# Per-file overview -----------------------------------------------------------
agg <- lapply(files, readRDS)
names(agg) <- sub("\\.rds$", "", basename(files))
overview <- bind_rows(lapply(names(agg), function(n) {
  k <- agg[[n]]$counters
  tibble(
    file = n, lines = k$lines, stdout = k$stdout, stderr = k$stderr,
    parse_share = if (k$stdout > 0) k$parse_ok / k$stdout else 0,
    first = as.Date(k$min_time), last = as.Date(k$max_time)
  )
})) |>
  mutate(role = ifelse(parse_share >= 0.5, "web", "other")) |>
  arrange(desc(lines))
web <- overview$file[overview$role == "web"]

by_class <- bind_rows(lapply(web, function(n) agg[[n]]$by_class)) |>
  summarise(requests = sum(requests), bytes = sum(bytes, na.rm = TRUE), .by = c(day, client_class))
by_status <- bind_rows(lapply(web, function(n) agg[[n]]$by_status)) |>
  summarise(requests = sum(requests), .by = c(day, status_class))
by_probe <- bind_rows(lapply(web, function(n) agg[[n]]$by_probe)) |>
  summarise(requests = sum(requests), .by = c(day, probe_family))

monthly <- by_class |>
  mutate(month = format(day, "%Y-%m")) |>
  summarise(requests = sum(requests), gb_out = gb(sum(bytes)), .by = month) |>
  arrange(month)

# September 2025 (the pitch's spike month) -----------------------------------
sep <- by_class |> filter(format(day, "%Y-%m") == "2025-09")
sep_days <- sep |>
  summarise(requests = sum(requests), gb_out = gb(sum(bytes)), .by = day) |>
  arrange(desc(gb_out))
sep_class <- sep |>
  summarise(requests = sum(requests), gb_out = gb(sum(bytes)), .by = client_class) |>
  mutate(share_bytes = gb_out / sum(gb_out)) |>
  arrange(desc(gb_out))
sep_probe <- by_probe |>
  filter(format(day, "%Y-%m") == "2025-09") |>
  summarise(requests = sum(requests), .by = probe_family) |>
  mutate(share = requests / sum(requests)) |>
  arrange(desc(requests))
sep_gb <- sum(sep$bytes) / 1e9

# Figures -----------------------------------------------------------------------
monthly_class <- by_class |>
  mutate(month = as.Date(paste0(format(day, "%Y-%m"), "-01")), client_class = factor(client_class, class_levels)) |>
  summarise(gb_out = gb(sum(bytes)), .by = c(month, client_class))
p10 <- ggplot(monthly_class, aes(month, gb_out, fill = client_class)) +
  geom_col(width = 25) +
  scale_fill_manual(values = class_colours, drop = FALSE) +
  labs(
    title = "Outgoing bytes per month in the historical logs",
    subtitle = "Web container only, by client class", x = NULL, y = "GB out (response bodies)",
    caption = "Source: historical Docker logs (KAP-104), aggregates."
  ) +
  theme_wta()
ggsave("analysis/figures/10_history_monthly_bytes.png", p10, width = 8, height = 4.5, dpi = 200, bg = surface)

if (nrow(sep) > 0) {
  p11 <- ggplot(mutate(sep, client_class = factor(client_class, class_levels)), aes(day, gb(bytes), fill = client_class)) +
    geom_col() +
    scale_fill_manual(values = class_colours, drop = FALSE) +
    labs(
      title = "September 2025: outgoing bytes per day", subtitle = "Web container only, by client class",
      x = NULL, y = "GB out", caption = "Source: historical Docker logs (KAP-104), aggregates."
    ) +
    theme_wta()
  ggsave("analysis/figures/11_history_sep2025_daily_bytes.png", p11, width = 8, height = 4.5, dpi = 200, bg = surface)
}

# Report ----------------------------------------------------------------------
lines <- c(
  "# Historical logs: June 2025 to May 2026 (KAP-104)", "",
  sprintf("Generated by `analysis/history_summary.R` on %s from `%s`. Aggregates only; the raw backup is local-only and was processed by the local worker.", format(Sys.Date()), in_dir), "",
  "## Files", "",
  md_table(transmute(overview,
    File = file, Lines = fmt(lines), stdout = fmt(stdout), stderr = fmt(stderr),
    `Apache share of stdout` = sprintf("%.1f%%", 100 * parse_share),
    From = format(first), To = format(last), Role = role
  )), "",
  sprintf("Files with role `web` (at least half of the stdout lines are Apache requests) are used below: %s.", paste(web, collapse = ", ")), "",
  "## Monthly volume (web container)", "",
  md_table(transmute(monthly, Month = month, Requests = fmt(requests), `GB out` = fmt(gb_out, 2))), "",
  "![Outgoing bytes per month](figures/10_history_monthly_bytes.png)", "",
  "*Figure 10. Outgoing response bytes per month in the historical logs, by client class.*", "",
  "## September 2025", "",
  sprintf("The pitch cited 64.3 GB incoming and 5.2 GB outgoing in 09/2025 (hosting-provider counters). The access log records outgoing response bodies only (`%%b`); these logs have no incoming bytes. Logged outgoing volume in September 2025: **%s GB** over %s requests.", fmt(sep_gb, 2), fmt(sum(sep$requests))), "",
  if (nrow(sep) > 0) c(
    "By client class:", "",
    md_table(transmute(sep_class, Class = client_class, Requests = fmt(requests), `GB out` = fmt(gb_out, 2), `Share of bytes` = sprintf("%.1f%%", 100 * share_bytes))), "",
    "Top 10 days by outgoing bytes:", "",
    md_table(transmute(head(sep_days, 10), Day = format(day), Requests = fmt(requests), `GB out` = fmt(gb_out, 2))), "",
    "Requests by probe family:", "",
    md_table(transmute(head(sep_probe, 12), Family = probe_family, Requests = fmt(requests), Share = sprintf("%.1f%%", 100 * share))), "",
    "![September 2025 daily bytes](figures/11_history_sep2025_daily_bytes.png)", "",
    "*Figure 11. Outgoing response bytes per day in September 2025, by client class.*", ""
  ) else c("The web container has no requests in September 2025.", ""),
  "## Caveats", "",
  "- Classification ran per chunk of the stream, so per-client rules (bursts, 404 ratio) can be slightly off at chunk boundaries. Totals, bytes, status and probe families are exact.",
  "- The old logs have no `CF-Connecting-IP` and no `%I`, so incoming volume is not visible and the human class may be under-counted (it requires Cloudflare-proxied browser traffic).",
  "- Response sizes count bodies only (`%b`), not headers or TLS overhead, so logged outgoing bytes are a lower bound of the provider's outgoing counter.",
  ""
)
writeLines(unlist(lines), "analysis/history_summary.md")
message("Wrote analysis/history_summary.md and figures 10, 11")
