Numbers below are from the tables above (rule order of decision 0002: declared crawlers are bots even on probe paths).

**What the data say.**

- **No human clients are reachable in this test.** All 5,137 `human` requests arrive through Cloudflare, so the direct-to-origin population has no client whose majority class is `human`. The check can therefore only compare scanner, bot and unknown (plus two internal clients). It says nothing about whether the human rule is right; that needs the Cloudflare-side client address (KAP-49) or the hand-labelled sample.
- **The structure is weak.** The silhouette rises monotonically from k = 2 (0.27) to k = 8 (0.38), the edge of the range. The gain at k = 6 to 8 comes from small, extreme clusters (about 50 clients) and from splitting the large mass of single-request clients, not from a clear natural k. Treat k = 8 as the best of a poor set, not as strong evidence of eight behaviours.
- **Agreement with the rules is low.** Purity at k = 8 is 0.67 against 0.61 for always predicting `scanner`, and the adjusted Rand index is 0.04 to 0.05. The unsupervised clusters recover almost none of the rule-based partition.

**Which clusters map to which class.**

- **Scanner-like clusters agree well.** At k = 8, one cluster of 440 clients has a 4xx share of 0.90 and a probe share of 0.92; it is 99% `scanner` (435 of 440). Another cluster of 361 clients has a 4xx share of 0.88, a probe share of 0.71 and about 150 requests per active hour; it is 81% scanner, 18% bot. At k = 4 the high-volume cluster (387 clients) is 82% scanner and the probe-heavy one (1,170 clients) is 90% scanner. Two more clusters with probe shares of 0.59 and 0.75 and a high share of requests without user agent (390 and 633 clients) are 85% and 74% scanner. High-volume, high-4xx, probing behaviour is what the scanner rule intends, and the clustering finds it independently.
- **A small heavy cluster is mixed.** The 49 clients that are active for about 27 days and send over 1,000 requests each (repetitive paths, 4xx share 0.42) are 57% scanner, 16% bot, 24% unknown (plus one internal client). These are persistent crawlers or monitors; the rule-based split between scanner and bot is not stable for them.
- **Bot clients are not separable.** Bots are 1% to 26% of every cluster at k = 8 and never the majority anywhere. Their behavioural features overlap with scanners (bots average a probe share of 0.18 and a 4xx share of 0.36 against 0.49 and 0.69 for scanners, but they are mixed into the same clusters). Bot is mostly defined by user agent, which is not among the clustering features.

**Where they disagree.**

- **`unknown` clients sit in quiet clusters, not in the scanner clusters.** `unknown` clients average a probe share of 0.02, a 4xx share of 0.18 and almost always send a user agent. The biggest `unknown` cluster (665 clients, 66% unknown, 4xx share 0.09) looks like low-volume visitors that a human would produce. Only 3 of 361 clients in the high-volume scanner cluster and 1 of 440 in the probe-heavy one are `unknown`. So the rules do not hide scanner behaviour in `unknown`; instead `unknown` mostly holds quiet clients that could be humans, search crawlers or one-off hits.
- **Many `scanner` clients do not look like scanners.** Of the 2,826 scanner-majority clients, 1,320 (47%) sent a single request and 1,243 land in the k = 3 cluster that is only 44% scanner (probe share 0.04). At k = 8, clusters 5 and 8 (2,124 clients with very low probe share, about two requests each, split into a daytime and a night-time cluster) are 57% and 42% scanner and hold 1,114 scanner clients, 39% of the class. The scanner rule evidently fires on signals outside these features (burst, user agent, a single high-risk path, a 404 for an unknown path), or flags one-off requests too eagerly. The rule is the more likely source of disagreement than the clusters.
- **Effect of the rule change (decision 0002).** Moving declared crawlers from `scanner` to `bot` made the scanner class cleaner (the high-volume scanner cluster is 81% scanner and the probe-heavy cluster 99%) but did not make bots separable by behaviour, since crawlers that probe look like scanners in these features.

**What it says about the rules.**

1. The scanner rule is well supported at the high-volume, high-error end.
2. The tail of single-request scanner labels is the weakest part and the first thing to inspect or hand-label (KAP-55, label sample). A single request carries too little behaviour for any per-client method, so this check cannot settle those cases either.
3. `unknown` is a legitimate residual class: it behaves like a quiet group, not like hidden scanners.
4. Humans must be validated separately, since none are visible here.

**Limits.** Direct-to-origin traffic is 39% of requests and is probably not representative of visitors, since humans mostly use Cloudflare. A client is an address, and addresses can be shared or rotate. About 46% of clients have a single request, so most features (active days, requests per hour) are degenerate for them. The silhouette is computed on a random sample of 3,000 clients. K-means assumes roughly spherical clusters on scaled features; the skewed shares make that rough.
