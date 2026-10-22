# Other services in the historical logs (KAP-104, KAP-54)

Generated on 2026-10-22 from monthly counts of the local-only backup `../data/vps_backup_20261007/`. Aggregates only: the counts came from a script run on Peter's PC (`~/.local/share/wta-kap104/monthly.py`), and the services were identified from masked line skeletons (letters → `a`, digits → `9`). No line content was read by any AI tool.

## What the five container logs are

| File | Lines | Service (from the line format) | Period |
|---|---|---|---|
| `container_331fe250…` | 355,936 | Apache, the current kapsiar.sk `web` container (`combined` format) | Jul to Oct 2026 |
| `container_7351262c…` | 22,493,977 | A Rust service (`tracing` format: timestamp, level, span fields, `crate::module` path), stderr only | Jun 2025 to May 2026 |
| `container_d653e38f…` | 5,863,190 | An Elixir/Phoenix web application (`request_id=… [info] GET /…` / `Sent 200 in …ms`) | Jun 2025 to May 2026 |
| `container_bc690daf…` | 163,347 | PostgreSQL (`host date time zone [pid] user@db LOG: …`, checkpoint statistics) | Jun 2025 to May 2026 |
| `container_e685adc0…` | 21,473 | Apache, an almost idle container: most request lines are TLS handshakes sent to a plain-HTTP port | Jun 2025 to May 2026 |

So the 2025 history of the kapsiar.sk website itself is **not** in the backup: the only Apache log covering September 2025 is the near-idle container.

## Monthly activity

| Month | Apache (idle container) lines | Phoenix app requests | Rust service lines (WARN) | PostgreSQL lines | Failed SSH logins |
|---|---|---|---|---|---|
| 2025-06 | 146 | 1,662 | 4,457 (2,222) | 2,658 | 234,666 |
| 2025-07 | – | – | – (–) | – | 235,783 |
| 2025-08 | 186 | 158,208 | 287 (196) | 11,455 | 321,743 |
| 2025-09 | 856 | 150,875 | 93,783 (84,744) | 38,365 | 269,422 |
| 2025-10 | 444 | 57,470 | 878,736 (865,438) | 59,733 | 210,558 |
| 2025-11 | 574 | 252,915 | 4,663,134 (4,663,134) | 1,847 | 348,451 |
| 2025-12 | 1,040 | 188,943 | 2,909,698 (2,903,584) | 19,688 | 320,448 |
| 2026-01 | 998 | 261,220 | 4,818,498 (4,818,498) | 2,516 | 463,282 |
| 2026-02 | 1,091 | 235,863 | 4,352,142 (4,352,142) | 4,236 | 416,308 |
| 2026-03 | 1,830 | 261,289 | 4,818,490 (4,818,490) | 3,721 | 428,171 |
| 2026-04 | 6,199 | 252,136 | 4,662,718 (4,662,718) | 8,902 | 299,109 |
| 2026-05 | 8,109 | 113,332 | 2,098,004 (2,098,004) | 10,226 | 242,268 |
| 2026-06 | – | – | – (–) | – | 116,104 |

`–` = no lines that month. July 2025 is missing from all container logs (the containers were probably recreated then).

## What this means for the September 2025 spike (KAP-54)

The provider reported 64.3 GB incoming and 5.2 GB outgoing in September 2025.

- **Apache (kapsiar.sk):** 848 requests and about 22 KB of response bodies. The website did not cause the spike.
- **Phoenix app:** 150,875 requests in September (about 5,000 a day). This is the only HTTP service with real volume. Its log has no byte counts, so its share of the traffic is unknown: 64.3 GB over 150,875 requests would be about 430 KB incoming per request, plausible only if the app received uploads or large payloads.
- **Rust service:** a constant WARN flood starts in September (93,783 lines) and reaches about 4.8 million lines a month from November. That looks like a retry or reconnect loop. A loop that keeps re-downloading or re-connecting can cause large incoming volume, so this is the main suspect, but its log has no byte counts either.
- **SSH brute force:** 269,422 failed logins in September 2025. That is in line with every other month (210k to 460k), so it is background noise, not a spike, and at a few KB per attempt it accounts for roughly 1 GB a month at most.
- **PostgreSQL:** busiest in September and October (38k and 60k log lines). Password failures appear only from January 2026 (293 in total), which suggests the database port became reachable from outside around then.
- Other incoming traffic that never shows up in container logs: Docker image pulls, package updates, backups and file syncs.

**Conclusion so far:** the HTTP logs cannot explain the 64.3 GB. The spike most likely came from the Rust service (whose WARN flood starts that month) or from the Phoenix app. Proving it needs either the provider's per-day traffic graph for September 2025 or knowing what the two services did. That is a question for Peter.

## Data-quality notes

- `btmp` holds 1,491,956 records with a zero or invalid timestamp (shown as 1970 to 2000). They are left out of the monthly figures.
- In the PostgreSQL log, client addresses appear in the line prefix, so the log is personal data. It stays local-only like the rest of the backup.
- `container_331fe250…` overlaps the analysed dataset (9 Jul to 3 Oct) and also covers the 3 to 7 October gap. Filling that gap would mean importing local-only rows into `data/processed/`, so it waits for Peter's decision.
