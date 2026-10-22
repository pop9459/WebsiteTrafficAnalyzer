# Progress log

Dated entries per phase report: done, decisions taken, open questions, what Peter must be able to explain, next.

## 2026-10-21: Phase R + A + first part of B (agent)

**Done**
- KAP-56 (`e6bdafc`): `R/aggregate.R` (`traffic_by_period`, `status_by_period`, `top_values`, `export_dashboard_json`) and `data-raw/export_dashboard.R`. TDD: red with 7 failing, then 22 new expectations passing.
- KAP-115 (`5357c6f`): research questions now use the current classifier shares (1.5% human, 85% scanner, 6.5% bot). Figure 01 regenerated.
- KAP-58 (`f1ad10f`): decision record `docs/decisions/0001-dashboard-architecture.md`, option (a) with JSON plus Chart.js.
- KAP-71 (`619ff19`): `parse_error_log()` with 43 new expectations, plus `analysis/error_log_summary.md`. All 44,530 error lines parse into 9 templates. 96% are "script not found" for probe paths. Spearman rho between scanner requests and error lines per hour is 0.80. No real site bugs.
- KAP-53 (`1cddc2a`): `analysis/data_quality.md` (Figures 7 and 8). 87 days, 1 gap day, referer 98% missing, user agent 13% missing, 1.3% exact-duplicate surplus rows, timestamps consistent with received times (p99 1 s).
- KAP-59: `traffic.php` with 4 Chart.js charts on the sample JSON. It is on personalWebsite branch `pop9459/kap-59-build-first-traffic-page-on-kapsiarsk`, pushed but **not merged to `live`**. Screenshots in `docs/screenshots/` (desktop and 375 px).
- AI record: `ai-sessions/collect.py` now includes Hermes sessions (29 sessions) and masked upload copies.
- Test suite: 145 passing. `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Decisions taken (veto-able)**
- Dashboard = option (a) with Chart.js 4.5.1 from jsDelivr (0001).
- Aggregation tests use a 6-row hand-checked fixture instead of the sample CSV, because `data/` is excluded from the package build.
- The JSON export is daily only; hourly data stays available through `unit = "hour"`.
- Top lists hide values with fewer than 5 requests and mask IPv4 addresses.
- Exact duplicate rows are kept (plausible same-second repeats).

**Open questions (to Peter)**
- Merge KAP-59 to `live`, which deploys the page publicly with sample data?
- Accept KAP-55, KAP-61 and KAP-62 as Done?
- Start KAP-104 (local-only historical logs) on the local worker now?
- Should the mid-term numbers include the VPS logs since 7 Oct?

**What Peter must be able to explain (T2a)**
- `R/aggregate.R` `top_values()`: why columns are allow-listed, why `min_requests` exists and why IPs are masked.
- `R/aggregate.R` `sum_or_na()`: why NA and not 0 for `bytes_in`.
- `R/errors.R` `parse_error_log()`: how the client IP is removed before anything is stored, and how templates group similar messages.
- Why option (a) was chosen in 0001.

**Next**
- KAP-70 human audience (`sessions_per_day()`), then KAP-69 clustering validation, then KAP-72 country/ASN.

## 2026-10-21 (later): steering answers applied

**Peter's answers**
- The dashboard lives on the personalWebsite project branch `pop9459/kap-10-traffic-dashboard`. It merges to `live` only when the project is done (KAP-116). Peter reviews on a local copy.
- KAP-55, KAP-61 and KAP-62 accepted as Done.
- KAP-104 runs tomorrow when the PC boots. Folding@home is disabled.
- Persisted server logs since 7 Oct: import them.

**Done**
- `500f931`: imported the server logs. Dataset now 9 Jul to 21 Oct 2026, 395,121 requests: scanner 82.9%, bot 8.3%, internal 6.0%, unknown 1.5%, human 1.3%. 61.1% of requests come via Cloudflare. All analyses re-run. `data_quality.R` now derives its prose from the data (extended-format rows, the 3-7 Oct export gap). `export_dashboard.R --out`.
- `970bb20`: chunked importer for the local-only backup (`R/history.R`, `data-raw/import_history.R`). Tested on synthetic data only. Suite 189, check clean.
- `c9e9986`: `analysis/history_summary.R` (input for KAP-54).
- personalWebsite `66c4829` on the project branch: demo fallback (`traffic.sample.json`), gitignored real `traffic.json`, `docker-compose.dev.yaml` on port 8095, README "Local review".
- Scheduled: `wta-kap104.timer` (22 Oct 07:00, runs at boot if missed), then the Hermes cron follow-up `6b3642db0d95` at 14:00.

**Decisions taken (veto-able)**
- The local-only run is a fixed script started by systemd, so no model reads the backup. The local worker only gives a second opinion on whether the outputs are clean, and a check that doesn't rely on any model is decisive. Reason: a long R run doesn't fit a model's tool timeout, and the script's output is aggregates by construction.
- `--chunk 500000`: a larger chunk keeps the per-client classification rules closer to a whole-file run.
- `research_questions.md` keeps the first-look numbers (labelled 9 Jul to 3 Oct).

**What Peter must be able to explain (T2a)**
- Why the historical import works per chunk, and what that does to the class split but not to the totals (`R/history.R`).

**Next**
- KAP-70 human audience, KAP-69 clustering, KAP-72 country/ASN.

## 2026-10-22: KAP-104 results and the September 2025 spike

**What happened**
- `wta-kap104` ran at boot (10:30 to 10:44). The import, summary and leak check all exited 0, and all outputs are CLEAN. The local worker step failed (exit 127): at boot the user manager's PATH has no `~/.local/bin`. Fixed in `job.sh`; re-run by hand, OVERALL CLEAN.
- The 14:00 cron follow-up stopped on that failed step, as designed, so it committed nothing.

**Done**
- `3fe97c0`: `analysis/history_summary.md` and `analysis/history_other_services.md`. The summary script now uses MB/KB, because GB showed 0.00, and no longer wrongly says "processed by the local worker".
- The backup is not the 2025 website history. It holds the current Apache container, a Rust service (22.5M WARN-heavy lines), an Elixir/Phoenix web app (about 2M requests), PostgreSQL and a near-idle Apache container. These were identified from masked line skeletons.
- KAP-54: the website logged 848 requests and about 22 KB in September 2025, so the 64.3 GB incoming was not HTTP traffic to kapsiar.sk. The main suspects are the Rust service (its WARN flood starts that month) and the Phoenix app (151k requests). SSH brute force is constant background at 210k-460k failed logins a month.
- Linear: KAP-104 Done, KAP-54 In Review.

**Decisions taken (veto-able)**
- Service formats were identified from skeletons (letters → `a`, digits → `9`), and monthly counts were computed locally. No line content reached an AI tool.
- The 3-7 Oct gap is not filled from `container_331fe250…`, because that would put local-only rows into `data/processed/`.

**Open questions (to Peter)**
- What were the Rust service and the Phoenix app on the VPS in 2025-26?
- Do you have the provider's per-day traffic graph for September 2025?
- Should the 3-7 Oct gap be filled from the backup's web container?

**Next (running now)**
- KAP-70 human audience, KAP-69 client clustering, KAP-72 country/ASN (DB-IP Lite).
