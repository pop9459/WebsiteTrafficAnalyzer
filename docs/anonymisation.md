# IP anonymisation

An IP address is personal data under the GDPR, and the course rules forbid identifiable records in AI tools. So anonymisation is the first processing step: nothing downstream (classification, aggregation, the dashboard, the committed sample) ever sees a real client address.

## What happens to each field

| Field | Treatment | Code |
|---|---|---|
| `ip` (client address) | Replaced by `ip_hash`: the first 16 hex characters of HMAC-SHA256(salt, ip) | `hash_ip()` in `R/anonymise.R` |
| `peer_ip` (connecting address, extended log format) | Used to derive `via_cloudflare`, then dropped | `anonymise_requests()` |
| `ident`, `user` | Dropped | `anonymise_requests()` |
| `query`, `request` | Not in the committed sample (query strings can carry personal data) | `data-raw/import_logs.R` |
| `referer` | Cut down to its host in the sample | `data-raw/import_logs.R` |
| IPv4 addresses inside `path` / `referer` | Replaced by `<ip>` in the sample and in the summary tables (proxy probes such as `CONNECT 203.0.113.9:80` put third-party addresses in the path) | `data-raw/import_logs.R`, `analysis/first_look.R` |

## Why a salted HMAC

- **Same client, same hash.** Requests can still be grouped per client (needed for the per-client scanner rule and the planned clustering) without storing the address.
- **Salt, not a plain hash.** The IPv4 space has only about 4 billion addresses, so an unsalted SHA-256 can be reversed by hashing every address. With a secret salt, a hash cannot be tested against guesses without the salt.
- **Truncation to 16 hex characters (64 bits).** Enough to avoid collisions among the few thousand clients in the logs, and it makes the value less usable as a stable identifier outside this project.

## The salt

- Read from the `WTA_SALT` environment variable, or from `~/.config/websitetrafficanalyzer/salt` (mode 0600, 32 random bytes from `openssl::rand_bytes()`); created on first import if missing (`get_salt(create = TRUE)`).
- Lives outside the repository. Losing it only means hashes from a later run cannot be matched to earlier ones; leaking it weakens the anonymisation, so rotate it if it leaks.
- Hashes from different salts are not comparable. Re-import everything with the same salt.

## Fields derived before hashing

Anything that needs the real address must be computed before `ip` is dropped, inside `anonymise_requests()`:

- `via_cloudflare`: whether the connecting address is in a Cloudflare range (`in_cloudflare()`, `R/cloudflare.R`). Done.
- Country and ASN: planned, see KAP-72. They must be added in this step, never later.

## Where raw data may live

- `data/raw/` (raw exports) and `data/processed/` (full anonymised tables) are git-ignored.
- Only `data/sample/requests_sample.csv` (2,000 random anonymised rows) and aggregates may be committed or put on the dashboard. CI and tests run on the committed sample and the synthetic fixture only.
- Raw log lines and real IPs are never pasted into AI tools or chats.

## Checks

- `tests/testthat/test-anonymise.R`: deterministic hashes that depend on the salt; empty salt refused; output contains no raw IP; `peer_ip` and `ident`/`user` removed; the committed sample contains no IP address outside the user-agent column.

## Limits

- Pseudonymised data is still personal data under the GDPR as long as the salt exists. Destroying the salt after the final import would make the data effectively anonymous, at the cost of not being able to re-link.
- Timestamps, user agents and paths can still single out a client in combination with outside knowledge; this is why only a sample and aggregates leave the machine.
