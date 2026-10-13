# Public datasets for comparison (KAP-62)

The CP1 feedback asked to compare kapsiar.sk's traffic with public data. This is the research step; the comparison itself is KAP-64 and answers RQ3 (`docs/research_questions.md`).

Research date: 2026-10-13. "Checked" means read on the source page; "unverified" means taken from a search summary or not found, and must be confirmed before it goes in the report.

## Candidates

| Dataset | What it contains | Format | Licence | Period | Fit with our logs | Status |
|---|---|---|---|---|---|---|
| **Cloudflare Radar** (API) | Global HTTP traffic trends, including the share of automated vs human requests (`botClass`: `LIKELY_HUMAN`, `LIKELY_AUTOMATED`), time series with intervals from 15 min to a month | JSON via free API (token needed) | CC BY-NC 4.0 (checked); fine for coursework, not commercial use | Rolling, recent | Good for **bot share**. Definitions differ (Cloudflare's own bot score vs our rules), and it describes traffic to Cloudflare customers, not one small site | Checked (docs); the exact bot-share endpoint name needs checking in the API reference |
| **monperrus/crawler-user-agents** (GitHub) | Regex patterns for known crawler user agents, with example UAs, operator URL and tags | One JSON file | MIT (checked) | Maintained list, 492 commits (checked) | Good for **validating the bot class**: what share of our user agents it recognises, and which of our "bot" UAs it does not. Says nothing about traffic volume; syntactic matching only, no accuracy figures | Checked |
| **NASA-HTTP** (Internet Traffic Archive) | All HTTP requests to the NASA Kennedy Space Center web server: about 3.46 million requests, July 1995 (31 days) plus part of August; host, timestamp, request, status, bytes | Plain text, Common Log Format | Free for research; the archive page states conditions, to be read again before citing (search summary) | 1995 | Good **baseline of a pre-scanner web**: status-code mix, hourly profile, file-type mix, share of 4xx. Very different era, site type and scale; only aggregate shapes are comparable, client-level comparison makes no sense | Partly checked (page did not load; facts from search summary) |
| **SecRepo** (secrepo.com) | Security-oriented sample data sets | Various | Site states CC BY 4.0 (checked) | Varies | The page did not list web-log samples at the time of checking, so it is not usable until a concrete file is found | Unverified, probably drop |
| **E-commerce access logs** (Zaker et al., 2019, "Harvard Dataverse") | Web server logs of an online shop | Unknown | Unknown | Unknown | Not found on Dataverse by search. A similar dataset exists in a paper by Chodak, Suchacka and Chawla (Computer Networks, 2020), "HTTP-level e-commerce data based on server access logs for an online store". Needs the DOI from the paper before it can be judged | Not verified, find the DOI before using it |
| **Threat-IP lists** (FireHOL blocklist-ipsets, AbuseIPDB) | IP addresses reported for scanning or abuse | Text lists / API | Per list; the repository README warns that some lists have special licences. AbuseIPDB free-tier limits not verified | Rolling | Would label scanner IPs, but only works on real IPs. That conflicts with the "hash first" rule unless done before hashing, and it adds privacy and terms questions for little gain over the probe-path rules we already have | Not recommended |

## Recommendation

Use three sources, each for one metric (all feed RQ3):

1. **Cloudflare Radar** for the **bot share**: our share of bot + scanner requests vs the global automated-traffic share. Caveat to state in the report: different definitions, and kapsiar.sk's tiny audience makes the share extreme.
2. **crawler-user-agents** for the **coverage of the bot class**: of our requests classified `bot`, what share has a user agent in the public list, and what do the unmatched ones look like. This also feeds the classifier validation in RQ1.
3. **NASA-HTTP** for the **status-code and hourly profile of a "clean" site**: share of 2xx/3xx/4xx, hour-of-day shape, so the report can show how far kapsiar.sk's 81% 4xx is from a normal site.

Skip threat-IP lists and SecRepo. Keep the e-commerce logs as optional, only if the DOI is found and it contains a post-2015 site.

## Comparison plan (for KAP-64)

| Metric | Our data | Public baseline | Method | Caveat |
|---|---|---|---|---|
| Automated share of requests | `client_class` in {bot, scanner} | Radar bot-class time series for the same dates (daily or weekly) | Side-by-side weekly share, plus difference in percentage points | Definitions differ |
| Bot UA coverage | Distinct UAs of class `bot` | crawler-user-agents regexes | Share matched; list the top unmatched UAs | Syntactic match only |
| Status-code mix | Share 2xx/3xx/4xx/5xx | NASA-HTTP | Bar chart of shares | 1995 vs 2026 |
| Hourly profile | Requests per hour of day, by class | NASA-HTTP, Radar | Normalised hourly curves | Time zones; NASA is US Eastern |

Planned code: a function reading the public sample files from `data/public/` (git-ignored if the licence prevents redistribution; only aggregates committed), and an analysis script `analysis/public_comparison.R`.

## To verify before the report
- Exact Radar endpoint and parameters for the human/automated share (API reference), and that a free API token is enough.
- NASA-HTTP usage conditions, quoted from the source page.
- The DOI of the e-commerce dataset, or drop it.
