# 0002. Declared crawlers are bots, even on probe paths

- Status: decided by Peter on 2026-10-22 (KAP-55, rule order)
- Context issues: KAP-55 (classifier rules), KAP-64 (public crawler list comparison)

## Context

`classify_requests()` applied its rules in the order internal → scanner → bot → human → unknown. A request for a probe path (`/.env`, `/.git/config`, `/wp-login.php`, ...) was therefore a scanner whatever the user agent said. The comparison with the public crawler list (KAP-64, `analysis/public_comparison.md`) showed the effect: 33.4% of the requests classified as scanner (109,514 of 327,606) had a user agent on the public list. The largest groups were Googlebot (29,225), meta-externalagent (8,175), CCBot (4,678) and ChatGPT-User (2,751), next to generic clients such as curl and Go-http-client. A crawler that names itself and asks for `/.env` is still a crawler; counting it as a scanner overstated the scanner share and understated the bot share.

## Options

| Option | Effect |
|---|---|
| (a) Keep the order: probe paths always mean scanner | Simple, but labels declared crawlers as scanners; 33.4% of scanner requests conflict with the public list |
| (b) Every bot-like user agent beats the path rule | Fixes crawlers, but curl, python-requests and similar tools are what scanners mostly use, so many scanners would become bots |
| (c) Declared crawlers beat the path rule, generic HTTP clients do not; scanning-tool user agents still win | Follows the user agent's own claim without trusting the generic tools |

## Decision

Option (c). Rule order is now: internal → scanner (scanning-tool user agent) → bot (declared crawler) → scanner (probe family, 4xx behaviour, 404 for an unknown path) → bot (generic client, no user agent, crawler-only path, burst) → human → unknown.

**Definition.** A declared crawler is a user agent that names a crawler, preview or monitoring product, i.e. it matches `crawler_ua_regex`: `bot|crawl|spider|slurp|externalagent|facebookexternalhit|ccbot|claude|perplexity|bytespider|fetcher|preview|monitor|uptime`. Generic HTTP libraries and tools do not count (`generic_client_ua_regex`: curl, wget, python, go-http, java/, okhttp, libwww, httpclient, axios, node-fetch, scrapy, headless, phantom), because scanners commonly use them. A request from a generic client on a probe path stays `scanner`. If the user agent matches `scanner_ua_regex` (nuclei, zgrab, ...) the request stays `scanner` even when the user agent also says "bot" (`Mozilla/5.0 (compatible; Nuclei bot)`). `bot_ua_regex` remains as the union of both patterns.

The rule also applies to the behavioural scanner rules (many 4xx, 404 for an unknown path), not only to probe paths: a declared crawler that gets 404s is still a crawler.

## Consequences

- The headline shares change on the full dataset (9 Jul – 21 Oct 2026, 395,121 requests): scanner 82.9% → 59.5%, bot 8.3% → 31.7%. Internal (6.0%), unknown (1.5%) and human (1.3%) are unchanged, because the rule only moves requests between scanner and bot.
- Numbers quoted for the earlier rule order (first look 9 Jul – 3 Oct, CP2 material) are historical and were not rewritten.
- The share of scanner requests that match the public crawler list falls from 33.4% to 13.2%; the rest are generic clients and scanning tools, which the list also contains.
- A crawler that fakes its user agent (a scanner calling itself "Googlebot") is now a bot. The rule trusts the declaration; verifying crawlers by reverse DNS or published IP ranges is not done.
- Bytes per class move too: the old "scanner" figures included crawler requests for probe paths.

## How to reverse

In `classify_requests()` (`R/classify.R`) delete the `declared_crawler ~ "bot"` line from the `case_when()`; the old order is restored. The two tests "a declared crawler is a bot even on probe paths" in `tests/testthat/test-classify.R` then need to be changed to the old expectations. Re-run `data-raw/import_logs.R` and the analysis scripts afterwards.
