# Research questions and measurable objectives (DRAFT for review)

KAP-61. Problem definition is graded once, at the mid-term, so every question below has a metric, a data source and a success criterion that can be checked with the data.

## Problem

kapsiar.sk is a small personal portfolio site, yet its traffic is far larger than expected (the pitch cited 64.3 GB incoming in 09/2025). The first look at the access log (9 Jul – 3 Oct 2026, 298,296 requests) shows why a plain traffic counter is not enough:

- Only about 1.5% of requests look human; about 85% come from scanners and 6.5% from known bots (classifier after KAP-55).
- Rule change (decision 0002, 22 Oct 2026): declared crawlers are now bots even on probe paths. On the full dataset (9 Jul – 21 Oct 2026, 395,121 requests) the shares are 59.5% scanner, 31.7% bot, 6.0% internal, 1.5% unknown and 1.3% human (before: 82.9% scanner, 8.3% bot); the figures above describe the period up to 3 Oct under the old rule order.
- 81% of requests end in a 4xx error.
- Scanners downloading the accidentally public `.git` folder caused about 95% of the outgoing bytes (9.07 of 9.51 GB).
- 56% of requests are logged with a Cloudflare address instead of the visitor's.

**Goal:** explain where the traffic comes from (humans, bots or scanners), show how it compares with public baselines, and derive concrete, evidence-based hardening steps for the site, presented in a dashboard on the site itself.

## Research questions

### RQ1 – Who sends the traffic?
*What share of requests and bytes comes from humans, bots and scanners, and how reliable is that split?*

| | |
|---|---|
| Metric | Share of requests and of outgoing bytes per class (human / bot / scanner / internal / unknown) |
| Data | Anonymised access log (`client_class` from `classify_requests()`), later enriched with country/ASN (KAP-72) |
| Success criteria | (a) Rule-based classifier agrees with independent labellers on ≥ 90% of the decisive rows of a fresh, stratified 200-request test sample (four AI labellers measured 98.1%, see `analysis/labelling/README.md`; AI labels are not ground truth, so a human check of disagreements is still advisable); (b) the share of `unknown` is ≤ 5% of requests; (c) an unsupervised clustering of clients (KAP-69) agrees with the rule classes on the large majority of clients, and disagreements are listed and explained |
| Issues | KAP-55, KAP-69, KAP-72 |

### RQ2 – What drives the volume, and can the incoming/outgoing volume be explained?
*Which paths, clients and times account for the traffic, who are the real human visitors, and does HTTP traffic explain the unexplained incoming volume?*

| | |
|---|---|
| Metric | Concentration (share of requests from the top 1% of clients; share of bytes per path family); daily and hourly profile per class; unique human visitors per day and top pages (KAP-70); incoming bytes (`%I`) vs outgoing bytes (`%O`) |
| Data | Access log, extended log format since KAP-49 (`%I %O %D`), historical logs (KAP-104), server-level counters for the incoming volume |
| Success criteria | (a) At least 90% of outgoing bytes attributed to named paths/classes (first result: 95% from the `.git` exposure); (b) the human audience is described by size, pages and referrers; (c) the 09/2025 incoming spike is either explained (≥ 80% of the volume attributed to a cause) or shown not to be HTTP traffic, with the evidence stated |
| Issues | KAP-70, KAP-54, KAP-104, KAP-56 |

### RQ3 – How does kapsiar.sk compare with public baselines?
*Is the bot share, status-code mix and scan behaviour of this site typical or unusual?* (CP1 teacher feedback)

| | |
|---|---|
| Metric | Bot share of requests vs the global bot share; status-code distribution vs a public access log; share of our bot user agents covered by a public crawler list |
| Data | 1–3 public datasets chosen in KAP-62 (see `docs/public_datasets.md`) |
| Success criteria | At least two metrics compared with a stated method and caveats (time period, site type, definition of "bot"); each difference of more than 10 percentage points is discussed with a likely cause |
| Issues | KAP-62, KAP-64 |

### RQ4 – Which security-relevant patterns appear, and what hardening do they justify?
*Which probing patterns and exposures occur, and what measurable effect does each fix have?*

| | |
|---|---|
| Metric | Requests per probe family; successful (2xx) probes per target; outgoing bytes before and after each fix; error-log findings (KAP-71) |
| Data | Access log, Apache error log, the before/after periods around the 7 Oct fix (KAP-68) |
| Success criteria | (a) Every probe family with a 2xx answer is explained, as exposure or as a false positive; (b) after the KAP-68 fix, outgoing bytes drop by ≥ 90% and no `/.git/*` request is answered with 2xx; (c) at least three hardening recommendations, each backed by a number from the data |
| Issues | KAP-68, KAP-71, KAP-103 |

## Out of scope
- Real-time blocking or a WAF; the project recommends measures, it does not build an IPS.
- Identifying individual visitors. All analysis uses salted hashes (`docs/anonymisation.md`).

## Known limitations to state in the report
- The classifier is rule-based and unvalidated until the hand-labelled set exists (RQ1a).
- Logs before 7 Oct 2026 do not record incoming bytes, and about 56% of older requests carry a Cloudflare address instead of the client's.
- The "2xx probe" counts include `proxy`-family requests (`GET http://…`, `CONNECT`) that the server may answer with its normal page; these need checking before they are called exposures (data-quality report, KAP-53).

## Questions to ask at CP2
1. Are four research questions the right amount for a solo project, or should RQ3 and RQ4 merge?
2. Is clustering a suitable independent check of a rule-based classifier?
3. Are the success thresholds (90% accuracy, 90% byte drop) ambitious enough without being arbitrary?
