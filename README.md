# trafficanalyzer

Analysis engine for the web-server access logs of [kapsiar.sk](https://kapsiar.sk), built as an R package for the NHL Stenden "Data Dynamics" solo project. The project asks where the site's traffic comes from: humans, bots or scanners.

Pipeline: read raw log → parse → anonymise IPs → classify → aggregate → dashboard.

## Setup

```r
renv::restore()
devtools::test()
```

IPs are hashed with a salted HMAC. The salt comes from the `WTA_SALT` environment variable or `~/.config/websitetrafficanalyzer/salt`, and is created on first import if missing. Never commit it.

## Running the pipeline

1. Put the raw export in `data/raw/`. This folder is git-ignored and raw logs are never committed. The export is either a copy of Docker's `*-json.log` or the output of `docker logs --timestamps web`.
2. Run `Rscript data-raw/import_logs.R`. It writes:
   - `data/processed/` (git-ignored)
   - `data/sample/requests_sample.csv`, an anonymised sample that is committed
3. Run `Rscript analysis/first_look.R` to write the figures in `analysis/figures/` and `analysis/first_look_summary.md`.

## Package functions

| Function | Purpose |
|---|---|
| `read_raw_log()` | Reads json-file, `--timestamps` or plain Apache logs (gz OK) |
| `parse_access_log()` | Parses Apache `combined` lines, with optional `%I %O %D` |
| `anonymise_requests()` | Adds `via_cloudflare` and `ip_hash`; drops the IP |
| `in_cloudflare()` | Checks whether an address is a Cloudflare edge address |
| `probe_family()` | Groups scanner paths (`.env`, `.git`, WordPress, …) into families |
| `classify_requests()` | First-pass `client_class`: human / bot / scanner / internal / unknown |
