**What the data say.**

- **No human clients are reachable in this test.** All 5,137 `human` requests arrive through Cloudflare, so the direct-to-origin population has no client whose majority class is `human`. The check can therefore only compare scanner, bot and unknown (plus two internal clients). It says nothing about whether the human rule is right; that needs the Cloudflare-side client address (KAP-49) or the hand-labelled sample.
- **The structure is weak.** The silhouette rises monotonically from k = 2 (0.27) to k = 8 (0.38), the edge of the range. The gain at k = 6 to 8 comes from small, extreme clusters (about 50 clients) and from splitting the large mass of single-request clients, not from a clear natural k. Treat k = 8 as the best of a poor set, not as strong evidence of eight behaviours.
- **Agreement with the rules is low.** Purity at k = 8 is 0.68 against 0.62 for always predicting `scanner`, and the adjusted Rand index is 0.02 to 0.06. The unsupervised clusters recover almost none of the rule-based partition.

**Which clusters map to which class.**

- **Scanner-like clusters agree well.** At k = 8, one cluster of 359 clients has the highest 4xx share (0.88), probe share (0.71) and about 150 requests per active hour. It is 99% `scanner`. The same pattern appears at k = 4 (387 clients, 99% scanner) and k = 3. Another cluster (538 clients) with a probe share near 0.8 and almost no user agent is 81% scanner and 19% bot. High-volume, high-4xx, probing behaviour is what the scanner rule intends, and the clustering finds it independently.
- **A small heavy cluster is mixed.** The 49 clients that are active for about 27 days and send over 1,000 requests each (repetitive paths, low 4xx) are 57% scanner, 16% bot, 25% unknown. These are persistent crawlers or monitors; the rule-based split between scanner and bot is not stable for them.
- **Bot clients are not separable.** Bots are 9% to 19% of every cluster at k = 8 and never the majority anywhere. Their behavioural features overlap with scanners (bots average a probe share of 0.13 and 4xx share of 0.28 against 0.49 and 0.69 for scanners, but they are mixed into the same clusters). Bot is mostly defined by user agent, which is not among the clustering features.

**Where they disagree.**

- **`unknown` clients sit in quiet clusters, not in the scanner cluster.** `unknown` clients average a probe share of 0.02, a 4xx share of 0.18 and almost always send a user agent. Two thirds of the biggest `unknown` cluster (681 clients, 65% unknown) look like low-volume visitors that a human would produce. Only 3 of 359 clients in the strongest scanner cluster are `unknown`. So the rules do not hide scanner behaviour in `unknown`; instead `unknown` mostly holds quiet clients that could be humans, search crawlers or one-off hits.
- **Many `scanner` clients do not look like scanners.** Of the 2,903 scanner-majority clients, 1,320 sent a single request and 1,250 land in the k = 3 cluster that is only 44.5% scanner (probe share 0.04). At k = 8, clusters 6 and 7 (1,661 clients with very low probe share, about one request each, split into a daytime cluster and a night-time cluster) are 47% to 51% scanner. The scanner rule evidently fires on signals outside these features (burst, user agent, a single high-risk path), or flags one-off requests too eagerly. Because these clients make up about 45% of the scanner class, the rule is the more likely source of disagreement than the clusters.

**What it says about the rules.**

1. The scanner rule is well supported at the high-volume, high-error end.
2. The tail of single-request scanner labels is the weakest part and the first thing to inspect or hand-label (KAP-55, label sample). A single request carries too little behaviour for any per-client method, so this check cannot settle those cases either.
3. `unknown` is a legitimate residual class: it behaves like a quiet group, not like hidden scanners.
4. Humans must be validated separately, since none are visible here.

**Limits.** Direct-to-origin traffic is 39% of requests and is probably not representative of visitors, since humans mostly use Cloudflare. A client is an address, and addresses can be shared or rotate. About 46% of clients have a single request, so most features (active days, requests per hour) are degenerate for them. The silhouette is computed on a random sample of 3,000 clients. K-means assumes roughly spherical clusters on scaled features; the skewed shares make that rough.
