# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Individual data science project (NHL Stenden, Semester 3 "Data Dynamics"). It analyses the web-server access logs of kapsiar.sk and shows the results as a traffic dashboard. The main question is where the site's unexplained traffic comes from (humans, bots or scanners). The results are compared with public datasets, as the teacher asked at the CP1 pitch.

- Planning lives in Linear: project P-KAP-5 "Solo Project – Web Traffic Log Analysis" (team KAPSLOK, issues `KAP-*`). Check the relevant issue before starting work. Each issue opens with a `**Caveman:**` one-line summary.
- Course requirements (report sections, rubric, deadlines) are in `../../MB - semester3 - student version - v4.8.pdf`. The pitch deck is `../projectPitchPresentation.pdf`.

## Communication style

Always use the `/caveman` skill (default level `full`) for replies in chat: invoke it at the start of every session. Stay terse. Keep only technical substance.

Write normal prose, not caveman, for anything stored outside the chat: code, comments, commit messages, docs, Linear issues and comments, and memory files.

## Commands

R package `trafficanalyzer` (usethis + renv + testthat 3e, roxygen docs). Run from the repo root:

```bash
Rscript -e 'renv::restore()'                     # install pinned packages
Rscript -e 'devtools::document()'                # regenerate NAMESPACE + man/ after roxygen edits
Rscript -e 'devtools::test()'                    # all tests
Rscript -e 'devtools::test(filter = "parse")'    # one test file (test-parse.R)
Rscript -e 'devtools::check(args = "--no-manual")'
Rscript data-raw/import_logs.R                   # data/raw/* -> data/processed/*.rds + data/sample/requests_sample.csv
Rscript analysis/first_look.R                    # figures + analysis/first_look_summary.md
Rscript data-raw/export_dashboard.R [--sample]   # dashboard aggregates -> data/processed/dashboard.json
```

Tests use only the synthetic fixture in `tests/testthat/fixtures/` (documentation IP ranges).

## Architecture

Pipeline: read logs → parse → anonymise → classify (human/bot/scanner) → aggregate → export JSON → dashboard. Built so far: everything up to the JSON export (`R/aggregate.R`, `data-raw/export_dashboard.R`), plus error-log parsing (`R/errors.R`), the chunked history importer (`R/history.R`), sessions (`R/sessions.R`), client features for clustering (`R/clients.R`) and geolocation (`R/geo.R`). The dashboard (option a, decision 0001) lives on the personalWebsite branch `pop9459/kap-10-traffic-dashboard`; it merges to `live` only when the project is done (KAP-116).

- **Engine:** an R package. Being an R package also replaces the course's CS50R packaging task, so keep it a proper package (DESCRIPTION, `R/`, `tests/testthat/`).
  - `R/read_logs.R` `read_raw_log()`: detects Docker json-file / `--timestamps` / plain Apache format.
  - `R/parse.R` `parse_access_log()`: regex for `combined` plus optional `%I %O %D`; non-matching lines keep a row with `parse_ok = FALSE`.
  - `R/anonymise.R`, `R/cloudflare.R` and `R/geo.R`: fields that need the real IP (`via_cloudflare`, `country`, `asn`, `as_org`) are derived in `anonymise_requests()` **before** `hash_ip()` replaces the IP.
  - `R/classify.R`: `probe_family()` (ordered regex families; the site's real PHP files are whitelisted in `site_php_regex`), then `classify_requests()` rules in order: internal → scanner → bot → human → unknown. This is a first pass; KAP-55 refines it.
  - `data-raw/` and `analysis/` are scripts, excluded from the package build.
- **Dashboard:** integrated into the existing website, not a standalone app. The website repo is `~/Documents/_MyProjects/personalWebsite`: PHP served by the `php:8.2-apache` Docker image, deployed by a webhook that git-pulls the `live` branch. The leading option is an R job that writes aggregated JSON, which a new PHP/JS page renders. Decided in `docs/decisions/0001-dashboard-architecture.md`: option (a), no Shiny or plumber.
- **Scheduled run on the VPS:** a containerised R job (KAP-60).

## Log source

- Until 7 Oct 2026 Apache in `php:8.2-apache` logged to stdout, so that history exists only in Docker exports. Since KAP-49 the logs are persisted on the host.
- Current logs are persisted on the VPS (`/var/log/website`, extended format with `%I %O %D` and the connecting address, since 7 Oct 10:28 UTC). Fetch them with `scripts/fetch_logs.sh` (read-only forced-command key, no root; see `docs/log_access.md`) into git-ignored `data/raw/vps/`. Do not ssh to the server as root, and keep the server's IP out of the repo (site is behind Cloudflare). The pre-7-Oct history exists only in the manual backup `../data/vps_backup_20261007/`.
- The pre-7-Oct backup `../data/vps_backup_20261007/` (5 gzipped json-file logs, up to 29M lines) is **local-only** and too large for memory. `Rscript data-raw/import_history.R [--out DIR] [--chunk N] FILE...` streams each file in chunks (`aggregate_log_chunk()` / `combine_history_chunks()`), prints and saves aggregates only (`data/processed/history/<file>.rds`, `history_daily.csv`) and guesses each file's role (`web` if at least half of the stdout lines parse as Apache, else `other`). Classification is per chunk, so burst and 404-ratio rules can be slightly off at chunk boundaries. It was developed on synthetic data only.
- Formats: `data/raw/personalwebsite_web_1_20261003-json.log.gz` (9 Jul–3 Oct 2026) is Docker's **json-file** log (`{"log","stream","time"}` per line; stderr = Apache error log) in plain `combined`. The server files since 7 Oct use the extended format with `%I %O %D` and the connecting address (`peer_ip`). The parser handles both. The analysed dataset (`data/processed/`) is both sources together: 9 Jul–21 Oct 2026, 395,121 requests, with a gap 3–7 Oct.
- The site is behind **Cloudflare**: about 61% of requests arrive via Cloudflare. In the old format the logged IP is then the edge, not the visitor, so per-client features only mean something for direct-to-origin traffic (`via_cloudflare == FALSE`). The extended format logs the visitor address with the edge in `peer_ip`.
- Until 7 Oct 2026 the whole website repo was the web root, so `/.git/` was publicly served and scanner downloads of `/.git/objects/` were ~95% of outgoing bytes. Fixed in KAP-68 (only `public/` is served); `analysis/fix_effect_summary.md` measures the effect.
- The 09/2025 "64 GB incoming" spike was not HTTP traffic to kapsiar.sk (848 requests that month); other services on the VPS are the suspects, see `analysis/history_other_services.md` (KAP-54).

## Progress tracking

- `docs/progress_log.md`: one dated entry per phase report (done, decisions taken, open questions, what Peter must be able to explain, next).
- `docs/decisions/NNNN-<slug>.md`: decision records (context, options, choice, why, how to reverse).
- Agent sessions on this project must end up in the AI record: run `python3 ../../ai-sessions/collect.py` after a work session (see that script's docstring).

## Data and privacy rules

- Raw logs go only in git-ignored `data/raw/`. Never commit raw logs, and never paste them or real IPs into AI tools. The course rules forbid identifiable records in AI tools.
- Anonymise IPs first with a salted HMAC. The salt lives outside the repo. Derive geo/ASN fields before hashing.
- Only anonymised samples (`data/sample/`) and aggregates may be committed or published on the dashboard.
- CI and tests must run on the committed sample data only.
