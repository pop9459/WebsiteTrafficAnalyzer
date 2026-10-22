# Comparison of kapsiar.sk traffic with public baselines (KAP-64, RQ3).
#
# Usage (from the repo root, after data-raw/import_logs.R and after putting
# the two public files in data/public/, see the Sources section of the report):
#   Rscript analysis/public_comparison.R
#
# Writes analysis/public_comparison.md and figures 17 to 19 to analysis/figures/.
# Aggregates only: no ip_hash, no IP address, no single user agent of a
# visitor is printed (user agents are reduced to product families and only
# families with at least 5 requests are listed).

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  devtools::load_all(quiet = TRUE)
})

invisible(Sys.setlocale("LC_TIME", "C"))

nasa_path <- "data/public/NASA_access_log_Jul95.gz"
crawler_path <- "data/public/crawler-user-agents.json"
stopifnot(file.exists(nasa_path), file.exists(crawler_path))

requests <- readRDS("data/processed/requests.rds")
dir.create("analysis/figures", showWarnings = FALSE)

surface <- "#fcfcfb"
kap_colour <- "#c8441a"
human_colour <- "#2a78d6"
nasa_colour <- "#52514e"

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
pval <- function(p) if (p < 2.2e-16) "< 2.2e-16" else sprintf("%.2g", p)

md_table <- function(df) {
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  )
}

# ---- Data ------------------------------------------------------------------

# Internal requests (own monitoring and tooling) are not visitors; leave them out
# of every share.
kap <- requests |> filter(client_class != "internal")
kap_humans <- kap |> filter(client_class == "human")
period <- sprintf("%s to %s", format(min(requests$time), "%d %b"), format(max(requests$time), "%d %b %Y"))

nasa_all <- read_clf_log(nasa_path)
nasa_unparsed <- sum(!nasa_all$parse_ok)
nasa <- filter(nasa_all, parse_ok)
rm(nasa_all)

status_levels <- c("2xx", "3xx", "4xx", "5xx")
status_counts <- function(status) {
  cls <- paste0(status %/% 100, "xx")
  as.integer(table(factor(cls, levels = status_levels)))
}

# ---- 1. Automated share ----------------------------------------------------

class_counts <- table(kap$client_class)
automated <- sum(class_counts[c("bot", "scanner")]) / sum(class_counts)
bot_share <- class_counts[["bot"]] / sum(class_counts)
scanner_share <- class_counts[["scanner"]] / sum(class_counts)
human_share <- class_counts[["human"]] / sum(class_counts)
unknown_share <- class_counts[["unknown"]] / sum(class_counts)

# Cloudflare: share of human HTML requests on 2 Dec 2025 (47%, blog post). The
# remainder is automated; this derived figure is not quoted by Cloudflare.
cf_human <- 0.47
cf_automated <- 1 - cf_human

# ---- 2. Crawler list coverage ----------------------------------------------

patterns <- load_crawler_patterns(crawler_path)
kap$matched <- match_crawler_ua(kap$user_agent, patterns)
kap$family <- ua_family(kap$user_agent)

coverage <- kap |>
  summarise(requests = n(), matched = sum(matched), .by = client_class) |>
  mutate(share = matched / requests) |>
  arrange(match(client_class, c("bot", "scanner", "human", "unknown")))

bot_cov <- coverage[coverage$client_class == "bot", ]
bot_no_ua <- sum(kap$client_class == "bot" & is.na(kap$user_agent))
bot_with_ua <- bot_cov$requests - bot_no_ua
bot_matched_of_ua <- bot_cov$matched / bot_with_ua

unmatched_bot <- kap |>
  filter(client_class == "bot", !matched, !is.na(family)) |>
  count(family, sort = TRUE) |>
  filter(n >= 5) |>
  slice_head(n = 10)

matched_scanner <- kap |>
  filter(client_class == "scanner", matched) |>
  count(family, sort = TRUE) |>
  filter(n >= 5) |>
  slice_head(n = 6)
matched_human <- kap |> filter(client_class == "human", matched) |> count(family, sort = TRUE) |> filter(n >= 5)
matched_scanner_total <- coverage$matched[coverage$client_class == "scanner"]

# ---- 3. Status mix and chi-squared -----------------------------------------

kap_status <- status_counts(kap$status)
human_status <- status_counts(kap_humans$status)
nasa_status <- status_counts(nasa$status)

cramers_v <- function(counts_a, counts_b) {
  keep <- counts_a + counts_b > 0
  tab <- rbind(counts_a[keep], counts_b[keep])
  test <- suppressWarnings(chisq.test(tab, correct = FALSE))
  list(test = test, v = sqrt(unname(test$statistic) / (sum(tab) * min(nrow(tab) - 1, ncol(tab) - 1))))
}
chi_all <- cramers_v(kap_status, nasa_status)
chi_human <- cramers_v(human_status, nasa_status)

status_tbl <- tibble(
  group = rep(c("kapsiar.sk, all visitors", "kapsiar.sk, humans only", "NASA-HTTP, July 1995"), each = length(status_levels)),
  status_class = rep(status_levels, 3),
  requests = c(kap_status, human_status, nasa_status)
) |>
  mutate(share = requests / sum(requests), .by = group)

# ---- 4. Hour-of-day profiles -----------------------------------------------

hour_profile <- function(time, tz) {
  h <- as.integer(format(time, "%H", tz = tz))
  counts <- as.integer(table(factor(h, levels = 0:23)))
  counts / sum(counts)
}
# NASA: the log's own offset is -0400 (US Eastern daylight time); Etc/GMT+4 is UTC-4.
nasa_local <- hour_profile(nasa$time, "Etc/GMT+4")
nasa_utc <- hour_profile(nasa$time, "UTC")
kap_local <- hour_profile(kap$time, "Europe/Bratislava")
human_local <- hour_profile(kap_humans$time, "Europe/Bratislava")
kap_utc <- hour_profile(kap$time, "UTC")
human_utc <- hour_profile(kap_humans$time, "UTC")

cor_tbl <- tibble(
  kapsiar = c("all visitors", "humans only"),
  local = c(cor(kap_local, nasa_local), cor(human_local, nasa_local)),
  utc = c(cor(kap_utc, nasa_utc), cor(human_utc, nasa_utc))
)

peak_hour <- function(p) which.max(p) - 1L
amplitude <- function(p) max(p) / min(p)

hours_tbl <- bind_rows(
  tibble(hour = 0:23, share = nasa_local, group = "NASA-HTTP 1995 (local, UTC-4)"),
  tibble(hour = 0:23, share = kap_local, group = "kapsiar.sk, all visitors (local, Europe/Bratislava)"),
  tibble(hour = 0:23, share = human_local, group = "kapsiar.sk, humans only (local, Europe/Bratislava)")
)

# ---- 5. Daily volume -------------------------------------------------------

nasa_daily <- nasa |> count(day = as.Date(time, tz = "Etc/GMT+4"))
kap_daily <- kap |> count(day = as.Date(time, tz = "UTC"))
human_daily <- kap_humans |> count(day = as.Date(time, tz = "UTC"))

# ---- Figures ---------------------------------------------------------------

group_colours <- c(
  "kapsiar.sk, all visitors" = kap_colour,
  "kapsiar.sk, humans only" = human_colour,
  "NASA-HTTP, July 1995" = nasa_colour
)

p17 <- ggplot(status_tbl, aes(status_class, share, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(
    aes(label = pct(share, 1)), position = position_dodge(width = 0.8),
    vjust = -0.4, size = 2.8, colour = "#52514e"
  ) +
  scale_fill_manual(values = group_colours) +
  scale_y_continuous(labels = scales::label_percent(), expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Status mix: kapsiar.sk against a 1995 web server",
    subtitle = sprintf("Share of requests by status class. Cramer's V: %.2f (all visitors), %.2f (humans only)", chi_all$v, chi_human$v),
    x = NULL, y = "Share of requests",
    caption = sprintf("Sources: kapsiar.sk access log, %s (internal requests excluded); NASA-HTTP trace, July 1995 (Internet Traffic Archive).", period)
  ) +
  theme_wta()
save_fig(p17, "17_status_mix_vs_nasa.png")

p18 <- ggplot(hours_tbl, aes(hour, share, colour = group)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.3) +
  scale_colour_manual(values = setNames(
    c(nasa_colour, kap_colour, human_colour),
    c("NASA-HTTP 1995 (local, UTC-4)", "kapsiar.sk, all visitors (local, Europe/Bratislava)", "kapsiar.sk, humans only (local, Europe/Bratislava)")
  )) +
  scale_x_continuous(breaks = seq(0, 23, 3)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  guides(colour = guide_legend(ncol = 1)) +
  labs(
    title = "Hour-of-day profile: kapsiar.sk against NASA-HTTP",
    subtitle = "Share of each source's requests per local hour of day",
    x = "Hour of day (local time of each source)", y = "Share of requests",
    caption = sprintf("Sources: kapsiar.sk access log, %s; NASA-HTTP trace, July 1995.", period)
  ) +
  theme_wta()
save_fig(p18, "18_hourly_profile_vs_nasa.png", height = 5)

cov_plot <- coverage |>
  mutate(label = sprintf("%s\n(n = %s)", client_class, num(requests)), label = factor(label, levels = label))
p19 <- ggplot(cov_plot, aes(label, share)) +
  geom_col(fill = kap_colour, width = 0.6) +
  geom_text(aes(label = pct(share, 1)), vjust = -0.4, size = 3, colour = "#52514e") +
  scale_y_continuous(labels = scales::label_percent(), limits = c(0, 1), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Share of requests whose user agent is in the public crawler list",
    subtitle = "By this project's client class; a match means the user agent fits a crawler-user-agents pattern",
    x = NULL, y = "Share matched",
    caption = sprintf("Sources: kapsiar.sk access log, %s; crawler-user-agents list (MIT).", period)
  ) +
  theme_wta()
save_fig(p19, "19_bot_ua_coverage.png")

# ---- Report ----------------------------------------------------------------

fam_table <- function(df) {
  if (nrow(df) == 0) return("(none with 5 or more requests)")
  md_table(tibble(`UA family` = df$family, Requests = num(df$n)))
}

status_wide <- do.call(rbind, lapply(unique(status_tbl$group), function(g) {
  d <- status_tbl[status_tbl$group == g, ]
  row <- as.list(setNames(sprintf("%s (%s)", pct(d$share), num(d$requests)), d$status_class))
  data.frame(group = g, row, check.names = FALSE)
}))

hour_summary <- tibble(
  Profile = c("NASA-HTTP 1995 (local)", "kapsiar.sk, all visitors (local)", "kapsiar.sk, humans only (local)"),
  `Busiest hour` = sprintf("%02d:00", c(peak_hour(nasa_local), peak_hour(kap_local), peak_hour(human_local))),
  `Busiest / quietest hour` = sprintf("%.1f", c(amplitude(nasa_local), amplitude(kap_local), amplitude(human_local)))
)

cor_md <- cor_tbl |>
  transmute(
    `kapsiar.sk group` = kapsiar,
    `Pearson r, local clocks` = sprintf("%.2f", local),
    `Pearson r, both in UTC` = sprintf("%.2f", utc)
  )

report <- c(
  "# Public comparison (KAP-64, RQ3)",
  "",
  sprintf(
    "kapsiar.sk access log, %s: %s requests from visitors (internal requests excluded), of which %s from humans. Aggregates only; the public files are downloaded to a git-ignored folder and are not part of the repository.",
    period, num(nrow(kap)), num(nrow(kap_humans))
  ),
  "",
  "## Sources",
  "",
  "| Source | What was used | Licence or conditions | Attribution |",
  "|---|---|---|---|",
  "| Cloudflare Radar, \"The 2025 Cloudflare Radar Year in Review\" (blog.cloudflare.com/radar-2025-year-in-review/, published 15 Dec 2025) | One published figure: the human share of HTML requests on 2 Dec 2025 | Published article. The Radar API itself is CC BY-NC 4.0 and needs a token, which this project does not have, so no API data was used | Cloudflare, Inc. |",
  "| crawler-user-agents (github.com/monperrus/crawler-user-agents), file `crawler-user-agents.json`, downloaded 22 Oct 2026 from raw.githubusercontent.com/monperrus/crawler-user-agents/master/crawler-user-agents.json | The `pattern` field of each entry (regular expressions): the file has 1,501 entries | MIT | The repository's copyright holders (GitHub user monperrus and contributors) |",
  "| NASA-HTTP, Internet Traffic Archive (ita.ee.lbl.gov/html/contrib/NASA-HTTP.html), file `NASA_access_log_Jul95.gz`, downloaded 22 Oct 2026 from ftp://ita.ee.lbl.gov/traces/NASA_access_log_Jul95.gz | All requests of 1-28 July 1995 | The archive page states under Restrictions: \"The traces may be freely redistributed.\" It also states under Privacy: \"Please do not however attempt any analysis beyond general traffic patterns.\" This report stays at the level of aggregate status and hourly shares | Trace collected by Jim Dumoulin of the Kennedy Space Center and contributed by Martin Arlitt and Carey Williamson of the University of Saskatchewan |",
  "",
  sprintf(
    "The NASA file holds %s lines. %s did not match the log pattern (a stray quote in the request) and are left out; the log's own times are in UTC-4. The archive page describes the file as July 1 to July 31; the last request in the file is on 28 July, so the file covers 28 days.",
    num(nrow(nasa) + nasa_unparsed), num(nasa_unparsed)
  ),
  "",
  "## Automated share vs Cloudflare",
  "",
  "Cloudflare's 2025 Year in Review states (HTML requests across its customer base, \"as of December 2, human traffic generated 47% of HTML requests, and non-AI bots generated 44%\"). The article notes that these shares are for HTML content only and differ from the all-content shares on Radar. Taking everything that is not human as automated gives about 53%; this subtraction is mine, not a figure Cloudflare publishes. The same article reports that AI bots made up 4.2% of HTML requests on average over 2025 and that Googlebot alone made up 4.5%.",
  "",
  md_table(tibble(
    Measure = c(
      "kapsiar.sk: bot + scanner",
      "kapsiar.sk: bot only",
      "kapsiar.sk: scanner only",
      "kapsiar.sk: human",
      "kapsiar.sk: unknown",
      "Cloudflare: human (HTML requests, 2 Dec 2025)",
      "Cloudflare: not human, derived (HTML requests)"
    ),
    Share = pct(c(automated, bot_share, scanner_share, human_share, unknown_share, cf_human, cf_automated))
  )),
  "",
  sprintf(
    "The kapsiar.sk automated share is %s, which is %.1f percentage points above the derived Cloudflare figure; the human share is %.1f points below. The two numbers are a single reference point against a whole period, not a time series. The definitions differ (see Limitations).",
    pct(automated), 100 * (automated - cf_automated), 100 * (cf_human - human_share)
  ),
  "",
  "## Bot UA coverage",
  "",
  sprintf(
    "Each request's user agent was matched against the %s patterns of the crawler list (case-sensitive, PCRE). A match means the user agent fits a known crawler pattern; it does not say the request was wanted or harmless.",
    num(length(patterns))
  ),
  "",
  md_table(tibble(
    `Client class` = coverage$client_class,
    Requests = num(coverage$requests),
    `Matched by list` = num(coverage$matched),
    Share = pct(coverage$share)
  )),
  "",
  sprintf(
    "- Of the %s requests classified bot, %s (%s) have a user agent in the list. %s of the bot requests carry no user agent at all and cannot match; among bot requests that do send one the share is %s.",
    num(bot_cov$requests), num(bot_cov$matched), pct(bot_cov$share), num(bot_no_ua), pct(bot_matched_of_ua)
  ),
  sprintf(
    "- Disagreement the other way: %s of the %s scanner requests (%s) also match the list. Most come from declared crawlers and generic HTTP clients that requested probe paths, so the classifier's scanner rule (which runs before the bot rule) puts them in the scanner class.",
    num(matched_scanner_total), num(coverage$requests[coverage$client_class == "scanner"]), pct(coverage$share[coverage$client_class == "scanner"])
  ),
  sprintf(
    "- Human requests matching the list: %s of %s (%s). Unknown: %s of %s (%s).",
    num(coverage$matched[coverage$client_class == "human"]), num(coverage$requests[coverage$client_class == "human"]), pct(coverage$share[coverage$client_class == "human"]),
    num(coverage$matched[coverage$client_class == "unknown"]), num(coverage$requests[coverage$client_class == "unknown"]), pct(coverage$share[coverage$client_class == "unknown"])
  ),
  "",
  "Top 10 user-agent families of bot requests that the list does not match (versions stripped; families with at least 5 requests):",
  "",
  fam_table(unmatched_bot),
  "",
  "Scanner requests that the list does match, by family (top families with at least 5 requests):",
  "",
  fam_table(matched_scanner),
  "",
  "![Share of requests matching the public crawler list, by client class](figures/19_bot_ua_coverage.png)",
  "",
  "## Status mix vs NASA",
  "",
  md_table(as.data.frame(status_wide)),
  "",
  sprintf(
    "Share of 4xx: kapsiar.sk %s for all visitors and %s for humans only; NASA-HTTP %s. No 1xx responses occur in any of the three groups.",
    pct(kap_status[3] / sum(kap_status)), pct(human_status[3] / sum(human_status)), pct(nasa_status[3] / sum(nasa_status))
  ),
  "",
  md_table(tibble(
    Comparison = c("kapsiar.sk all visitors vs NASA", "kapsiar.sk humans only vs NASA"),
    `Chi-squared (df = 3)` = sprintf("%.0f", c(chi_all$test$statistic, chi_human$test$statistic)),
    `p-value` = c(pval(chi_all$test$p.value), pval(chi_human$test$p.value)),
    `Cramer's V` = sprintf("%.2f", c(chi_all$v, chi_human$v))
  )),
  "",
  sprintf(
    "With samples of this size (%s, %s and %s requests) any difference is significant, so the p-values say little; Cramer's V is the effect size. V is %.2f for all visitors, which is a very large difference, and %.2f for humans only, which is %s. The chi-squared test treats every request as independent, which logs violate (one client sends many requests), so the p-values are optimistic even before the sample-size issue.",
    num(sum(kap_status)), num(sum(human_status)), num(sum(nasa_status)), chi_all$v, chi_human$v,
    if (chi_human$v < 0.1) "small" else if (chi_human$v < 0.3) "small to moderate" else "moderate or larger"
  ),
  "",
  "![Status class mix, kapsiar.sk against NASA-HTTP](figures/17_status_mix_vs_nasa.png)",
  "",
  "## Hourly profile",
  "",
  "Hour-of-day shares were computed in each source's local time (NASA UTC-4; kapsiar.sk Europe/Bratislava, which is where the site's owner and most human visitors are expected; this is an assumption, since the log has no visitor time zone) and, as a check, with both sources in UTC.",
  "",
  md_table(hour_summary),
  "",
  md_table(cor_md),
  "",
  sprintf(
    "NASA's 1995 profile has a clear working-day shape (busiest/quietest ratio %.1f). The kapsiar.sk all-visitor profile has a ratio of %.1f and the human profile %.1f. Pearson r of the 24 shares is %.2f for all visitors and %.2f for humans only on local clocks, and %.2f and %.2f in UTC. Each correlation is based on 24 points, and the human profile rests on only %s requests over %s days.",
    amplitude(nasa_local), amplitude(kap_local), amplitude(human_local),
    cor_tbl$local[1], cor_tbl$local[2], cor_tbl$utc[1], cor_tbl$utc[2],
    num(nrow(kap_humans)), num(length(unique(as.Date(kap_humans$time))))
  ),
  "",
  sprintf(
    "Daily volume: NASA-HTTP has a median of %s requests per day (%s days); kapsiar.sk has a median of %s requests per day for all visitors and %s for humans only (%s days with traffic).",
    num(round(median(nasa_daily$n))), nrow(nasa_daily), num(round(median(kap_daily$n))), num(round(median(human_daily$n))), nrow(kap_daily)
  ),
  "",
  "![Hour-of-day profile, kapsiar.sk against NASA-HTTP](figures/18_hourly_profile_vs_nasa.png)",
  "",
  "## Limitations",
  "",
  "- **Era.** NASA-HTTP is from 1995: HTTP/1.0, before today's scanners and AI crawlers. Differences reflect 31 years of web change as much as anything about kapsiar.sk.",
  "- **Site type.** NASA ran a popular public information site with a staff audience in one time zone; kapsiar.sk is a personal site with a tiny audience, an exposed web root and mostly unwanted traffic. Neither is a sample of \"the web\".",
  "- **Scale.** NASA's file has about 370 times as many requests as kapsiar.sk's human traffic. Only aggregate shapes are compared; client-level comparison makes no sense, and the NASA page asks users to stay with general traffic patterns.",
  "- **Definitions.** Cloudflare classifies each request with its own bot score across its customer base and, in the figure used here, only for HTML requests. This project classifies by rules on paths, user agents and behaviour, over all content types. The crawler list matches user-agent strings only and says nothing about accuracy; a spoofed user agent matches, a crawler with a unique string does not. The classifier and the list are not independent: both use user-agent strings.",
  "- **Cloudflare figure.** One published number for one date (2 Dec 2025), outside the kapsiar.sk period, read from an article; no time series, and the \"not human\" share is derived by subtraction.",
  "- **Time zones.** kapsiar.sk hours are shown in Europe/Bratislava as an assumption about the audience; scanners run around the clock regardless.",
  "",
  "## Implications",
  "",
  sprintf(
    "- RQ3: kapsiar.sk is far more automated than the public reference. About %s of its requests are bot or scanner traffic, against roughly %s non-human HTML requests reported by Cloudflare across its customers. The gap is large, but the definitions differ, so the direction is solid and the exact size is not.",
    pct(automated, 0), pct(cf_automated, 0)
  ),
  sprintf(
    "- The status mix is the clearest contrast: %s of requests to kapsiar.sk are 4xx against %s at NASA, with V = %.2f. Probing for paths that do not exist produces that pattern; a clean public site does not. For humans alone the 4xx share is %s, which is higher than NASA's %s but only by a few percentage points.",
    pct(kap_status[3] / sum(kap_status), 0), pct(nasa_status[3] / sum(nasa_status)), chi_all$v,
    pct(human_status[3] / sum(human_status)), pct(nasa_status[3] / sum(nasa_status))
  ),
  sprintf(
    "- Classifier validation (RQ1): the public list recognises %s of bot requests and %s of those that send a user agent. The unmatched bot requests are mostly browser-like user agents that the classifier labelled bot by behaviour, which a user-agent list cannot confirm or refute. %s of scanner requests match the list, which shows that the scanner rule overrides declared crawlers that request probe paths; whether such requests should be counted as bots or as scanners is a definition question for the report.",
    pct(bot_cov$share), pct(bot_matched_of_ua), pct(coverage$share[coverage$client_class == "scanner"])
  ),
  "- The hourly comparison supports only a weak claim, because the human sample is small; see the correlations above."
)

writeLines(report, "analysis/public_comparison.md")
cat("wrote analysis/public_comparison.md\n")
