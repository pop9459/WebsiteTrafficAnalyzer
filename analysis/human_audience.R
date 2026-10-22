# The real human audience of kapsiar.sk (KAP-70).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/human_audience.R
#
# Writes analysis/human_audience.md and figures 12 and 13 to analysis/figures/.
# Aggregates only: no ip_hash, no single user agent, no IP address is printed.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  devtools::load_all(quiet = TRUE)
})

invisible(Sys.setlocale("LC_TIME", "C"))

requests <- readRDS("data/processed/requests.rds")
dir.create("analysis/figures", showWarnings = FALSE)

surface <- "#fcfcfb"
human_colour <- "#2a78d6"

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

pct <- function(x, digits = 1) sprintf(paste0("%.", digits, "f%%"), 100 * x)
num <- function(x) format(x, big.mark = ",", trim = TRUE)

# Markdown table from a data frame, all columns as given.
md_table <- function(df) {
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  )
}

source_caption <- sprintf(
  "Source: kapsiar.sk access log, %s to %s, human requests only.",
  format(min(requests$time), "%d %b"), format(max(requests$time), "%d %b %Y")
)

human <- requests |>
  filter(client_class == "human") |>
  mutate(
    day = as.Date(time, tz = "UTC"),
    hour = as.integer(format(time, "%H")),
    minute = as.integer(format(time, "%M")),
    client = paste(ip_hash, user_agent)
  )

# 1. Scheduled monitors -------------------------------------------------------
# Is any human client hitting the site at a fixed minute of the hour on many days?
monitor_check <- function(df, min_days, min_share) {
  per_client <- df |>
    group_by(client) |>
    summarise(
      n = n(), days = n_distinct(day),
      top_minute_share = max(table(minute)) / n(),
      .groups = "drop"
    )
  c(
    clients_with_days = sum(per_client$days >= min_days),
    monitors = sum(per_client$days >= min_days & per_client$top_minute_share >= min_share)
  )
}
page_loads <- filter(human, path == "/")
mon_all <- monitor_check(human, 5, 0.8)
mon_loads <- monitor_check(page_loads, 5, 0.8)
mon_loose <- monitor_check(page_loads, 3, 0.5)

hour_counts <- count(human, hour) |> right_join(tibble(hour = 0:23), by = "hour") |>
  mutate(n = coalesce(n, 0L))
spike_share <- sum(hour_counts$n[hour_counts$hour %in% c(6, 13, 18)]) / sum(hour_counts$n)
hour_chisq <- chisq.test(hour_counts$n)
peak_hours <- hour_counts |> arrange(desc(n)) |> slice(1:3)
low_hours <- hour_counts |> arrange(n) |> slice(1:3)

# 2. Sessions ---------------------------------------------------------------
sessions <- sessions_per_day(requests)
all_days <- tibble(day = seq(min(as.Date(requests$time, tz = "UTC")), max(as.Date(requests$time, tz = "UTC")), by = "day"))
sessions <- all_days |> left_join(sessions, by = "day") |>
  mutate(across(c(sessions, clients, requests), ~ coalesce(.x, 0L)))
sessions$trend <- vapply(seq_len(nrow(sessions)), function(i) {
  mean(sessions$sessions[max(1, i - 6):i])
}, numeric(1))
sessions$trend[seq_len(6)] <- NA

# Session shape, using the same rule as sessions_per_day() but per session.
sessions_all <- human |>
  arrange(client, time) |>
  group_by(client) |>
  mutate(session = cumsum(c(TRUE, diff(as.numeric(time)) / 60 >= 30))) |>
  group_by(client, session) |>
  summarise(
    n = n(), first = min(time), last = max(time), loads = sum(path == "/"),
    .groups = "drop"
  ) |>
  mutate(minutes = as.numeric(difftime(last, first, units = "mins")))
client_days <- human |> group_by(client) |> summarise(days = n_distinct(day), .groups = "drop")

# 3. Pages, referrers, devices, browsers --------------------------------------
site_page <- is_site_page(human$path)
pages <- human[site_page, ] |>
  count(path, name = "requests", sort = TRUE) |>
  filter(requests >= 5) |>
  mutate(share = pct(requests / sum(requests)), requests = num(requests))
page_requests_total <- sum(site_page)

ref_host <- referer_host(page_loads$referer)
ref_host[page_loads$referer %in% c("-", "")] <- NA
ref_self <- ref_host %in% c("kapsiar.sk", "www.kapsiar.sk")
ref_table <- tibble(host = ref_host[!is.na(ref_host) & !ref_self]) |>
  count(host, name = "page_loads", sort = TRUE) |>
  filter(page_loads >= 5) |>
  slice(1:10)

ua <- page_loads$user_agent
device <- ifelse(grepl("Mobile|Android|iPhone|iPad", ua), "mobile", "desktop")
browser <- case_when(
  grepl("Edg/|EdgA/|EdgiOS/", ua) ~ "Edge",
  grepl("Firefox/|FxiOS/", ua) ~ "Firefox",
  grepl("Chrome/|CriOS/", ua) ~ "Chrome",
  grepl("Safari/", ua) ~ "Safari",
  .default = "other"
)
split_table <- function(x, levels) {
  tibble(group = factor(x, levels = levels)) |>
    count(group, .drop = FALSE) |>
    mutate(share = pct(n / sum(n)), page_loads = num(n)) |>
    select(group, page_loads, share)
}
device_table <- split_table(device, c("desktop", "mobile"))
browser_table <- split_table(browser, c("Chrome", "Firefox", "Safari", "Edge", "other"))

# Figures -----------------------------------------------------------------------
p12 <- ggplot(sessions, aes(day)) +
  geom_col(aes(y = sessions), fill = human_colour, alpha = 0.45, width = 1) +
  geom_line(aes(y = trend), colour = human_colour, linewidth = 0.8, na.rm = TRUE) +
  scale_y_continuous(expand = expansion(c(0, 0.05))) +
  labs(
    title = "The site gets a few dozen human visits a day",
    subtitle = "Human sessions per day (gap of 30 minutes ends a session); line = 7-day mean",
    x = NULL, y = "Sessions", caption = source_caption
  ) +
  theme_wta()
save_fig(p12, "12_human_sessions_per_day.png")

p13 <- ggplot(hour_counts, aes(hour, n)) +
  geom_col(fill = human_colour, width = 0.8) +
  geom_hline(yintercept = mean(hour_counts$n), linetype = "dashed", colour = "#52514e", linewidth = 0.4) +
  scale_x_continuous(breaks = seq(0, 23, 3)) +
  scale_y_continuous(expand = expansion(c(0, 0.05))) +
  labs(
    title = "Human requests are spread over the whole day",
    subtitle = "Human requests by hour of day (UTC); dashed line = mean per hour. No spike at 06, 13 or 18",
    x = "Hour (UTC)", y = "Requests", caption = source_caption
  ) +
  theme_wta()
save_fig(p13, "13_human_hour_of_day.png")

# Markdown --------------------------------------------------------------------
n_days <- nrow(sessions)
lines <- c(
  "# The human audience of kapsiar.sk",
  "",
  sprintf("Generated by `analysis/human_audience.R` on %s. Aggregates only (KAP-70).", format(Sys.Date())),
  "",
  "## Dataset",
  "",
  sprintf(
    "- %s requests from %s to %s (%d days, UTC). %s requests (%s) are classified as human.",
    num(nrow(requests)), format(min(requests$time), "%d %b"), format(max(requests$time), "%d %b %Y"),
    n_days, num(nrow(human)), pct(nrow(human) / nrow(requests))
  ),
  sprintf(
    "- Human means a browser user agent on a request that came through Cloudflare (see `classify_requests()`). All of them are Cloudflare requests, so the address in the log is a shared edge address; sessions are approximate."
  ),
  sprintf(
    "- %s distinct clients (ip_hash plus user agent). %s of them were seen on more than one day.",
    num(n_distinct(human$client)), pct(mean(client_days$days > 1))
  ),
  "",
  "## Are scheduled monitors hiding in the human class?",
  "",
  "An earlier figure (`05_hour_of_day_by_class.png`) showed human hits peaking at 06, 13 and 18 UTC, which looked like uptime monitors with browser user agents. I checked this with the current classifier.",
  "",
  sprintf(
    "- Share of human requests in hours 06, 13 and 18: %s. A flat distribution would give %s. The spike is gone.",
    pct(spike_share), pct(3 / 24)
  ),
  sprintf(
    "- Busiest hours: %s (%s requests); quietest: %s (%s). The mean is %s per hour. The counts are not perfectly uniform (chi-square p %s 0.001), but no hour stands out the way 06, 13 and 18 did.",
    paste(sprintf("%02d", peak_hours$hour), collapse = ", "), paste(peak_hours$n, collapse = ", "),
    paste(sprintf("%02d", low_hours$hour), collapse = ", "), paste(low_hours$n, collapse = ", "),
    round(mean(hour_counts$n)), ifelse(hour_chisq$p.value < 0.001, "<", ">=")
  ),
  sprintf(
    "- Clients whose requests fall at least 80%% in the same minute of the hour, on at least 5 days: **%d** of %d clients active on 5 or more days (%d of %d when only page loads of `/` are used; %d when the test is loosened to 50%% on 3 days).",
    mon_all[["monitors"]], mon_all[["clients_with_days"]], mon_loads[["monitors"]], mon_loads[["clients_with_days"]], mon_loose[["monitors"]]
  ),
  "",
  "Conclusion: with the current rules and data there are no fixed-minute monitors left in the human class, so I do not propose a classifier change. I did not check which earlier rules produced the spike; the data now shows none. If monitors with browser user agents come back, the test above (same minute of the hour on 5 or more days, at least 80% of a client's human requests) is the rule I would add to `classify_requests()`.",
  "",
  "![Human requests by hour](figures/13_human_hour_of_day.png)",
  "",
  "## Visits per day",
  "",
  "A session is a run of requests from one client (ip_hash and user agent) without a gap of 30 minutes or more, counted on the day it starts (`sessions_per_day()`).",
  "",
  sprintf(
    "- Median **%.0f sessions per day** (mean %.1f, range %d to %d) over %d days; %d days had no human session.",
    median(sessions$sessions), mean(sessions$sessions), min(sessions$sessions), max(sessions$sessions), n_days, sum(sessions$sessions == 0)
  ),
  sprintf(
    "- %s sessions in total, from a median of %.0f distinct clients per day.",
    num(sum(sessions$sessions)), median(sessions$clients)
  ),
  sprintf(
    "- A median session has %.0f request. %s of sessions are a single request, and %s of sessions contain a request for `/`. Sessions with more than one request (%s of all) have a median of %.0f requests and %.1f minutes between first and last request.",
    median(sessions_all$n), pct(mean(sessions_all$n == 1)), pct(mean(sessions_all$loads > 0)),
    pct(mean(sessions_all$n > 1)), median(sessions_all$n[sessions_all$n > 1]),
    mean(sessions_all$minutes[sessions_all$n > 1])
  ),
  "",
  "![Human sessions per day](figures/12_human_sessions_per_day.png)",
  "",
  "## Pages",
  "",
  sprintf(
    "Only real site paths are counted (`/`, `/index.php` and the PHP content files), not scripts, styles or the favicon. They account for %s of the %s human requests. The site is a single page (KAP-112), so `/` dominates.",
    pct(page_requests_total / nrow(human)), num(nrow(human))
  ),
  "",
  md_table(pages),
  "",
  "## Referrers",
  "",
  sprintf(
    "Referrer host of the %s human page loads of `/`: %s have no referrer (typed address, bookmark, or a browser or app that strips it) and %s come from the site itself. Hosts with at least 5 page loads:",
    num(nrow(page_loads)), pct(mean(is.na(ref_host))), pct(mean(ref_self, na.rm = TRUE))
  ),
  "",
  md_table(mutate(ref_table, share = pct(page_loads / sum(!is.na(ref_host) & !ref_self)), page_loads = num(page_loads))),
  "",
  "The share column is of the page loads that have an external referrer.",
  "",
  "## Devices and browsers",
  "",
  sprintf("Based on the %s human page loads of `/`. Mobile means the user agent contains Mobile, Android, iPhone or iPad.", num(nrow(page_loads))),
  "",
  md_table(device_table),
  "",
  md_table(browser_table),
  "",
  "## Limits",
  "",
  "- All human requests arrive through Cloudflare, so the logged address is an edge address shared between visitors. Two visitors with the same browser on the same edge can merge into one client, and one visitor can appear on several edges. Sessions are approximate, and probably an under-count.",
  "- The human class only has browser user agents on non-probe paths. A person whose browser requested a missing file is classified as scanner (404 rule), and a person who reached the origin directly is classified as unknown; both are left out.",
  "- A browser user agent can be faked; the 'human' label means 'looks like a normal browser visit', not proof of a person.",
  "- The user-agent device and browser split is a simple regex and lumps all Chromium-based browsers other than Edge under Chrome.",
  "",
  "## Implications",
  "",
  "- The real audience is small: tens of sessions a day against thousands of scanner requests. Dashboard figures for humans should show sessions, not raw requests.",
  "- Nothing needs to change in the human rule for monitors. Re-run the check in this script after the classifier changes.",
  "- Referrers are mostly empty, so the dashboard should not promise an acquisition breakdown beyond a short list of hosts.",
  "- `sessions_per_day()` is ready to export for the dashboard; it needs the Cloudflare caveat next to the number."
)
writeLines(lines, "analysis/human_audience.md")
cat("wrote analysis/human_audience.md and figures 12, 13\n")
