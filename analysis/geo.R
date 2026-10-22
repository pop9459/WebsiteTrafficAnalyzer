# Where do scanners come from? Country and ASN of direct-to-origin traffic (KAP-72).
#
# Usage (from the repo root, after data-raw/import_logs.R with the DB-IP
# databases in place):
#   Rscript analysis/geo.R
#
# Writes analysis/geo_summary.md and figures 15 and 16. Aggregates only; only
# countries and ASNs with at least 5 distinct clients are listed.
# IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

requests <- readRDS("data/processed/requests.rds")
direct <- requests |> filter(via_cloudflare %in% FALSE, !is.na(country))
if (!nrow(direct)) stop("No geo data in requests.rds: run data-raw/import_logs.R with the DB-IP databases.")

min_clients <- 5
attribution <- "IP Geolocation by DB-IP (https://db-ip.com)"
class_levels <- c("scanner", "bot", "human", "unknown", "internal")
class_colours <- c(human = "#2a78d6", bot = "#eb6834", scanner = "#1baf7a", unknown = "#eda100", internal = "#e87ba4")
surface <- "#fcfcfb"

theme_wta <- function() {
  theme_minimal(base_size = 11) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank(),
      axis.text = element_text(colour = "#52514e"),
      axis.title = element_text(colour = "#52514e"),
      plot.title = element_text(colour = "#0b0b0b", face = "bold"),
      plot.subtitle = element_text(colour = "#52514e"),
      plot.caption = element_text(colour = "#52514e", hjust = 0)
    )
}
save_fig <- function(plot, name, height = 5) {
  ggsave(file.path("analysis/figures", name), plot, width = 8, height = height, dpi = 200, bg = surface)
}
caption <- sprintf("Direct-to-origin requests only (%s). %s.", format(nrow(direct), big.mark = ","), attribution)

# Cloud / hosting providers: case-insensitive keyword match on the AS organisation.
hosting_keywords <- c(
  "amazon", "google", "microsoft", "digitalocean", "digital ocean", "ovh", "hetzner",
  "linode", "akamai", "alibaba", "tencent", "contabo", "m247", "vultr", "choopa",
  "oracle", "cloud", "hosting", "datacamp", "leaseweb", "scaleway", "online s.a.s",
  "ionos", "stark industries", "pq hosting", "kamatera", "colocrossing", "psychz"
)
hosting_regex <- paste(hosting_keywords, collapse = "|")
direct <- direct |> mutate(hosting = grepl(hosting_regex, as_org, ignore.case = TRUE))

md_table <- function(df) {
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
fmt <- function(x) format(x, big.mark = ",", trim = TRUE)

# Countries per class -------------------------------------------------------
by_country <- direct |>
  group_by(client_class, country) |>
  summarise(requests = n(), clients = n_distinct(ip_hash), .groups = "drop") |>
  filter(clients >= min_clients)
top_country <- by_country |>
  group_by(client_class) |>
  slice_max(requests, n = 8, with_ties = FALSE) |>
  ungroup() |>
  mutate(client_class = factor(client_class, levels = class_levels))

p15 <- ggplot(top_country, aes(requests, reorder(country, requests), fill = client_class)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~client_class, scales = "free", ncol = 2) +
  scale_fill_manual(values = class_colours) +
  scale_x_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.08))) +
  labs(title = "Top countries per client class", x = "Requests", y = NULL,
       subtitle = "Countries with at least 5 distinct clients", caption = caption) +
  theme_wta()
save_fig(p15, "15_top_countries_by_class.png", height = 6.5)

# ASNs for scanners ---------------------------------------------------------
scanners <- direct |> filter(client_class == "scanner", !is.na(asn))
by_asn <- scanners |>
  group_by(asn) |>
  summarise(as_org = names(sort(table(as_org), decreasing = TRUE))[1],
            requests = n(), clients = n_distinct(ip_hash), hosting = any(hosting), .groups = "drop") |>
  filter(clients >= min_clients) |>
  arrange(desc(requests))
top_asn <- head(by_asn, 15) |>
  mutate(label = paste0("AS", asn, " ", substr(as_org, 1, 30)))

p16 <- ggplot(top_asn, aes(requests, reorder(label, requests))) +
  geom_col(fill = class_colours[["scanner"]]) +
  scale_x_continuous(labels = scales::label_comma(), expand = expansion(c(0, 0.08))) +
  labs(title = "Top networks (ASNs) sending scanner traffic", x = "Scanner requests", y = NULL,
       subtitle = "ASNs with at least 5 distinct scanner clients", caption = caption) +
  theme_wta()
save_fig(p16, "16_top_asns_scanners.png", height = 5.5)

# Hosting share ---------------------------------------------------------------
class_hosting <- direct |>
  group_by(client_class) |>
  summarise(requests = n(), clients = n_distinct(ip_hash),
            hosting_req = mean(hosting), hosting_clients = n_distinct(ip_hash[hosting]) / n_distinct(ip_hash),
            .groups = "drop") |>
  arrange(desc(requests))
sc <- class_hosting |> filter(client_class == "scanner")

# Markdown ---------------------------------------------------------------------
class_tbl <- class_hosting |>
  transmute(class = client_class, requests = fmt(requests), clients = fmt(clients),
            `requests from hosting ASNs` = sprintf("%.0f%%", 100 * hosting_req),
            `clients in hosting ASNs` = sprintf("%.0f%%", 100 * hosting_clients))
country_tbl <- by_country |> filter(client_class == "scanner") |> arrange(desc(requests)) |> head(10) |>
  transmute(country, share = sprintf("%.1f%%", 100 * requests / sum(direct$client_class == "scanner")),
            requests = fmt(requests), clients = fmt(clients)) |>
  select(country, requests, clients, share)
asn_tbl <- head(by_asn, 15) |>
  transmute(asn = paste0("AS", asn), organisation = as_org, requests = fmt(requests),
            clients = fmt(clients), hosting = ifelse(hosting, "yes", "no"))

md <- c(
  "# Where scanners come from: country and ASN (KAP-72)",
  "",
  sprintf("*%s.* Data: DB-IP Lite country and ASN databases (CC BY 4.0), looked up on the real IP inside `anonymise_requests()` before hashing.", attribution),
  "",
  "## Scope",
  "",
  sprintf("- Only direct-to-origin requests (`via_cloudflare == FALSE`): %s requests, %s distinct clients. Requests through Cloudflare carry an edge address, so country and ASN are `NA` there.",
          fmt(nrow(direct)), fmt(n_distinct(direct$ip_hash))),
  sprintf("- Only countries and ASNs with at least %d distinct clients are listed. Aggregates only.", min_clients),
  "- Geolocation is approximate (country level); an ASN identifies the network operator, not the person.",
  "",
  "## Client class by hosting provider",
  "",
  "Hosting/cloud = the AS organisation name matches one of these keywords (case-insensitive): ",
  paste0(paste(hosting_keywords, collapse = ", "), "."),
  "The list is a heuristic: broad words like `cloud` or `hosting` also catch some non-hosting networks, and VPN or proxy providers outside the list are missed.",
  "",
  md_table(class_tbl),
  "",
  sprintf("**Scanners: %.0f%% of scanner requests and %.0f%% of scanner clients sit in hosting/cloud ASNs.**",
          100 * sc$hosting_req, 100 * sc$hosting_clients),
  "",
  "## Top countries of scanner traffic",
  "",
  md_table(country_tbl),
  "",
  "![Top countries per class](figures/15_top_countries_by_class.png)",
  "",
  "## Top ASNs of scanner traffic",
  "",
  md_table(asn_tbl),
  "",
  "![Top scanner ASNs](figures/16_top_asns_scanners.png)",
  ""
)
writeLines(md, "analysis/geo_summary.md")
cat(sprintf("Wrote analysis/geo_summary.md and 2 figures (%d direct requests).\n", nrow(direct)))
