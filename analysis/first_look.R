# First look at the kapsiar.sk access logs (KAP-8).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/first_look.R
#
# Writes figures to analysis/figures/ and headline numbers to
# analysis/first_look_summary.md. Both contain aggregates only.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

invisible(Sys.setlocale("LC_TIME", "C"))

requests <- readRDS("data/processed/requests.rds")
errors <- readRDS("data/processed/errors.rds")
dir.create("analysis/figures", showWarnings = FALSE)

# Reference palette (validated: categorical slots 1-5, light surface).
class_levels <- c("human", "bot", "scanner", "unknown", "internal")
class_colours <- c(human = "#2a78d6", bot = "#eb6834", scanner = "#1baf7a", unknown = "#eda100", internal = "#e87ba4")
status_colours <- c("2xx" = "#2a78d6", "3xx" = "#eb6834", "4xx" = "#1baf7a", "5xx" = "#eda100")
surface <- "#fcfcfb"

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

source_caption <- sprintf(
  "Source: kapsiar.sk access log, %s to %s, %s requests.",
  format(min(requests$time), "%d %b"), format(max(requests$time), "%d %b %Y"),
  format(nrow(requests), big.mark = ",")
)

requests <- requests |>
  mutate(
    client_class = factor(client_class, levels = class_levels),
    status_class = paste0(status %/% 100, "xx"),
    day = as.Date(time),
    week = as.Date(cut(time, "week")),
    hour = as.integer(format(time, "%H"))
  )

# 1. Requests per week by client class --------------------------------------
weekly <- count(requests, week, client_class)
p1 <- ggplot(weekly, aes(week, n, fill = client_class)) +
  geom_col(colour = surface, linewidth = 0.4, width = 6) +
  scale_fill_manual(values = class_colours) +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.05))) +
  labs(
    title = "Most traffic to kapsiar.sk comes from scanners",
    subtitle = "Requests per week, by client class (rule-based first pass)",
    x = NULL, y = "Requests", caption = source_caption
  ) +
  theme_wta()
save_fig(p1, "01_requests_per_week_by_class.png")

# 2. Requests per day by status class ---------------------------------------
daily_status <- count(requests, day, status_class)
p2 <- ggplot(daily_status, aes(day, n, colour = status_class)) +
  geom_line(linewidth = 0.7) +
  scale_colour_manual(values = status_colours) +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.05))) +
  labs(
    title = "Client errors (4xx) dominate every day",
    subtitle = "Requests per day, by HTTP status class",
    x = NULL, y = "Requests", caption = source_caption
  ) +
  theme_wta()
save_fig(p2, "02_requests_per_day_by_status.png")

# 3. What scanners look for --------------------------------------------------
families <- requests |>
  filter(probe_family != "none") |>
  count(probe_family, sort = TRUE) |>
  mutate(probe_family = reorder(probe_family, n))
p3 <- ggplot(families, aes(n, probe_family)) +
  geom_col(fill = class_colours[["scanner"]], width = 0.7) +
  geom_text(aes(label = scales::comma(n)), hjust = -0.15, size = 3.2, colour = "#52514e") +
  scale_x_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.15))) +
  labs(
    title = "Scanners mostly hunt for PHP shells, secrets and source code",
    subtitle = "Requests per probe family",
    x = "Requests", y = NULL, caption = source_caption
  ) +
  theme_wta() +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "#e6e5e1", linewidth = 0.3))
save_fig(p3, "03_probe_families.png")

# 4. Probes that succeeded ---------------------------------------------------
exposed <- requests |>
  filter(probe_family != "none", probe_family != "malformed", status >= 200, status < 300) |>
  mutate(target = case_when(
    grepl("^/\\.git/objects/", path) ~ "/.git/objects/*",
    grepl("^/\\.git/(refs|logs)/", path) ~ sub("^(/\\.git/(refs|logs)/).*$", "\\1*", path),
    .default = path
  ))
exposed_targets <- exposed |>
  group_by(probe_family, target) |>
  summarise(requests = n(), clients = n_distinct(ip_hash), bytes = sum(bytes), .groups = "drop") |>
  arrange(desc(requests))

top_exposed <- head(exposed_targets, 12) |> mutate(target = reorder(target, requests))
p4 <- ggplot(top_exposed, aes(requests, target)) +
  geom_col(fill = "#d03b3b", width = 0.7) +
  geom_text(aes(label = scales::comma(requests)), hjust = -0.15, size = 3.2, colour = "#52514e") +
  scale_x_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.15))) +
  labs(
    title = "Exposed: the site's .git folder is publicly downloadable",
    subtitle = "Probe requests answered with HTTP 2xx, top 12 targets",
    x = "Requests answered with 2xx", y = NULL, caption = source_caption
  ) +
  theme_wta() +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "#e6e5e1", linewidth = 0.3))
save_fig(p4, "04_exposed_probe_targets.png")

# 5. Hour of day by class ----------------------------------------------------
hourly <- requests |>
  filter(client_class != "internal") |>
  count(hour, client_class) |>
  group_by(client_class) |>
  mutate(share = n / sum(n)) |>
  ungroup()
p5 <- ggplot(hourly, aes(hour, share, colour = client_class)) +
  geom_line(linewidth = 0.7) +
  scale_colour_manual(values = class_colours) +
  scale_x_continuous(breaks = seq(0, 23, 3)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(c(0, 0.05)), limits = c(0, NA)) +
  labs(
    title = "'Human' traffic spikes at fixed hours: likely scheduled monitors",
    subtitle = "Share of each class's requests per hour of day (UTC). The human rule needs refining (KAP-55)",
    x = "Hour (UTC)", y = "Share of the class's requests", caption = source_caption
  ) +
  theme_wta()
save_fig(p5, "05_hour_of_day_by_class.png")

# Headline numbers -----------------------------------------------------------
by_class <- requests |>
  group_by(client_class) |>
  summarise(
    requests = n(),
    via_cloudflare = mean(via_cloudflare),
    gb_out = sum(bytes) / 1e9,
    .groups = "drop"
  ) |>
  mutate(share = requests / sum(requests), .after = requests)

direct_clients <- n_distinct(requests$ip_hash[!requests$via_cloudflare])
cf_edges <- n_distinct(requests$ip_hash[requests$via_cloudflare])
days <- as.numeric(difftime(max(requests$time), min(requests$time), units = "days"))

human_pages <- requests |>
  filter(client_class == "human", status < 400, method == "GET", !grepl("\\.(js|css|map|png|jpe?g|svg|webp|ico|woff2?|ttf|pdf|mp4|json|txt|xml)$", path)) |>
  count(path, sort = TRUE) |>
  head(10)

fmt_table <- function(df) {
  df <- mutate(df, across(where(is.numeric), ~ format(round(.x, 3), big.mark = ",")))
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |"))
  )
}

summary_lines <- c(
  "# First look: kapsiar.sk access logs",
  "",
  paste0("Generated by `analysis/first_look.R` on ", format(Sys.Date()), ". Aggregates only."),
  "",
  "## Dataset",
  "",
  sprintf("- %s requests over %.0f days (%s per day), plus %s error-log lines.",
          format(nrow(requests), big.mark = ","), days, format(round(nrow(requests) / days), big.mark = ","),
          format(nrow(errors), big.mark = ",")),
  sprintf("- %.1f%% of requests arrive through Cloudflare (%d edge addresses); %.1f%% hit the origin server directly (%s distinct clients).",
          100 * mean(requests$via_cloudflare), cf_edges, 100 * mean(!requests$via_cloudflare), format(direct_clients, big.mark = ",")),
  sprintf("- %.1f%% of all requests end in 4xx; %.1f%% in 2xx.",
          100 * mean(requests$status_class == "4xx"), 100 * mean(requests$status_class == "2xx")),
  sprintf("- %s requests (%.1f%%) are not valid HTTP (e.g. TLS handshakes on port 80).",
          format(sum(requests$probe_family == "malformed"), big.mark = ","), 100 * mean(requests$probe_family == "malformed")),
  sprintf("- Outgoing response bytes: %.2f GB in total, of which %.2f GB (%.0f%%) answered probes for exposed files (mostly `/.git/objects/`).",
          sum(requests$bytes) / 1e9, sum(exposed$bytes) / 1e9, 100 * sum(exposed$bytes) / sum(requests$bytes)),
  "",
  "## Requests by client class",
  "",
  fmt_table(by_class),
  "",
  "## Probe families",
  "",
  fmt_table(as.data.frame(families) |> mutate(probe_family = as.character(probe_family)) |> arrange(desc(n))),
  "",
  "## Probes answered with 2xx (exposure)",
  "",
  sprintf("%s probe requests from %s distinct clients got a 2xx answer.",
          format(nrow(exposed), big.mark = ","), format(n_distinct(exposed$ip_hash), big.mark = ",")),
  "",
  fmt_table(head(exposed_targets, 20)),
  "",
  "## Most visited pages by humans",
  "",
  fmt_table(human_pages)
)
writeLines(summary_lines, "analysis/first_look_summary.md")
cat(summary_lines, sep = "\n")
