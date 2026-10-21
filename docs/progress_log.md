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
