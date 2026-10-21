# 0001. Dashboard architecture: R writes JSON, the website renders it

- Status: proposed by the agent on 2026-10-21; Peter to confirm or veto (KAP-58)
- Context issues: KAP-58 (decision), KAP-59 (first page), KAP-60 (scheduled run)

## Context

The analysis engine is an R package. The dashboard has to live inside the existing website (kapsiar.sk), not as a separate app. The website is a PHP site served by the `php:8.2-apache` container on a small VPS, deployed by a webhook that pulls the `live` branch. Only aggregated, anonymised numbers may be published (privacy rules in `CLAUDE.md`).

## Options

| Criterion | (a) R job writes JSON, PHP/JS page renders it | (b) Shiny app behind a reverse proxy, embedded in an iframe | (c) plumber REST API queried by the page's JS |
|---|---|---|---|
| Privacy | Only the aggregates in the JSON leave the server; the raw data is never reachable from the web | The app process holds the full data; a bug can expose rows | The API process holds the full data; every endpoint has to be checked |
| Extra running services | None: a scheduled container run writes a file | A long-running R server (memory on a small VPS) | A long-running R server |
| Attack surface | A static JSON file | A web application plus WebSocket | An HTTP API with query parameters |
| Interactivity | Client-side only: filters over the pre-aggregated data | Full server-side interactivity | Live queries |
| Look and feel | Same HTML/CSS as the site | Shiny's own look in an iframe | Same as the site |
| Effort | Low: one export function plus one page | Medium: new service, proxy, auth | Medium: new service, endpoints, CORS |
| Fits the deploy model | Yes: the page ships with the site, the JSON comes from the job | No: needs new infrastructure | No: needs new infrastructure |

## Decision

Option (a). `export_dashboard_json()` (KAP-56) writes one JSON file with daily aggregates and top lists. A page `traffic.php` in the website repo loads it and draws the charts with Chart.js 4 from a CDN, so the site does not need a build step. KAP-60 will run the R pipeline on a schedule and write the JSON into the site's `public/json/` folder.

## Consequences

- Interactivity is limited to what the pre-aggregated data allows. Filters by class and date range work, but ad-hoc queries over single requests do not, and this is intended.
- The JSON format is the contract between the two repos. Any change to `export_dashboard_json()` must keep the page working; the tests in `tests/testthat/test-aggregate.R` pin the top-level fields.
- Values with fewer than 5 requests are left out of the top lists, and IPv4 addresses are masked, so rare or identifying strings never reach the page.
- Until KAP-60 runs, the page shows the committed 2,000-request sample and says so.

## How to reverse

The engine does not depend on this choice. Switching to (b) or (c) later would reuse the same aggregation functions; only the page and the scheduled job would be replaced.
