# trafficanalyzer

<!-- badges: start -->
[![R-CMD-check](https://github.com/pop9459/WebsiteTrafficAnalyzer/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pop9459/WebsiteTrafficAnalyzer/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

Analysis engine for the web-server access logs of [kapsiar.sk](https://kapsiar.sk), built as an R package for the NHL Stenden "Data Dynamics" solo project. The project asks where the site's traffic comes from: humans, bots or scanners.

Pipeline: read raw log → parse → anonymise IPs → classify → aggregate → dashboard.

## Setup

```r
renv::restore()
devtools::test()
```

IPs are hashed with a salted HMAC. The salt comes from the `WTA_SALT` environment variable or `~/.config/websitetrafficanalyzer/salt`, and is created on first import if missing. Never commit it.

## Geolocation data

`anonymise_requests()` adds `country`, `asn` and `as_org` from the free DB-IP Lite databases if they are present in `~/.local/share/websitetrafficanalyzer/geo/` (or `WTA_GEO_DIR`): `dbip-country-lite-YYYY-MM.csv.gz` and `dbip-asn-lite-YYYY-MM.csv.gz` from https://db-ip.com/db/lite.php. Without them the columns are `NA`. IP Geolocation by DB-IP (https://db-ip.com), licensed under CC BY 4.0.

## Running the pipeline

1. Put the raw export in `data/raw/`. This folder is git-ignored and raw logs are never committed. The export is either a copy of Docker's `*-json.log` or the output of `docker logs --timestamps web`.
2. Run `Rscript data-raw/import_logs.R`. It writes:
   - `data/processed/` (git-ignored)
   - `data/sample/requests_sample.csv`, an anonymised sample that is committed
3. Run `Rscript analysis/first_look.R` to write the figures in `analysis/figures/` and `analysis/first_look_summary.md`.
4. Run `Rscript data-raw/export_dashboard.R` to write the dashboard aggregates to `data/processed/dashboard.json` (git-ignored). With `--sample` it uses only the committed sample and writes `data/sample/dashboard_sample.json`.

## Scheduled run on the server

`deploy/` holds a container that turns the server's Apache logs into the dashboard JSON every night (KAP-60). Server steps, resource use and rollback are in `docs/deploy.md`.

## Package functions

| Function | Purpose |
|---|---|
| `read_raw_log()` | Reads json-file, `--timestamps` or plain Apache logs (gz OK) |
| `parse_access_log()` | Parses Apache `combined` lines, with optional `%I %O %D` |
| `anonymise_requests()` | Adds `via_cloudflare` and `ip_hash`; drops the IP |
| `in_cloudflare()` | Checks whether an address is a Cloudflare edge address |
| `probe_family()` | Groups scanner paths (`.env`, `.git`, WordPress, …) into families |
| `classify_requests()` | Rule-based `client_class`: human / bot / scanner / internal / unknown |
| `traffic_by_period()` | Requests, clients and bytes per day/hour and client class |
| `status_by_period()` | Status-class counts and shares per day/hour |
| `top_values()` | Top paths, user agents or referer hosts per class (IPs masked, minimum count) |
| `parse_error_log()` | Parses Apache/PHP error-log lines into module, level, `AH` code, PHP error type and a grouped `message_template` (client IPs dropped) |
| `export_dashboard_json()` | Writes all dashboard aggregates to one JSON file |
| `sessions_per_day()` | Visits per day: consecutive requests of one client (ip_hash + user agent) with gaps under `gap_minutes` (default 30); approximate behind Cloudflare |
| `client_features()` | One row per direct-to-origin client with 8 behaviour features and its majority class; input for the clustering check (KAP-69) |
| `load_geo_db()`, `geo_lookup()` | DB-IP Lite country and ASN lookup (IPv4/IPv6) used by `anonymise_requests()` before hashing |
| `load_crawler_patterns()`, `match_crawler_ua()` | Flags user agents listed in the public crawler-user-agents list (KAP-64) |
| `ua_family()` | Reduces a user agent to its product family, without versions |
| `read_clf_log()` | Reads a Common Log Format file such as the NASA-HTTP trace |
| `aggregate_log_chunk()`, `combine_history_chunks()` | Chunked aggregates (per day: class, status, probe family, clients) of huge json-file logs; used by `data-raw/import_history.R` (KAP-104) |
