# Scheduled analysis on the VPS (KAP-60)

A nightly job turns the persisted Apache logs into `public/json/traffic.json`, which the dashboard reads. This is a draft: nothing here has been applied to the server yet.

## What it does

```
/var/log/website/access.log*  (read-only mount, gz is fine)
   -> parse -> anonymise (salted HMAC, geo derived first) -> classify -> aggregate
   -> /out/traffic.json.tmp -> atomic rename -> public/json/traffic.json
```

- Everything runs in one short-lived container (`wta-analyzer`), started by a systemd timer at 03:30 UTC (`Persistent=true`, so a missed run happens at next boot).
- Only `access.log`, `access.log.N` and `access.log.N.gz` are read. Error logs and `other_vhosts_access.log` are ignored.
- The output holds aggregates only (daily counts, top paths, user agents, referrers, status codes). The local test found no IPv4 address in it.
- Any failure exits non-zero, removes the temp file and leaves the previous `traffic.json` untouched. The dashboard keeps showing the last good file.
- The container prints only aggregate lines: file/line/request counts, date range, class counts, elapsed seconds, peak memory. No log lines, no IPs.

Files (all in this repo, under `deploy/`):

| File | Purpose |
|---|---|
| `Dockerfile` | Two-stage build on `rocker/r-ver:4.6.1`; packages pinned by `renv.lock`; runs as non-root user `wta` |
| `pipeline.R` | The R pipeline |
| `run_pipeline.sh` | Entrypoint: checks salt/mounts, runs R, atomic rename, clear errors |
| `compose.kap60.yaml` | Override file for `/root/personalWebsite` (service `analyzer`, profile `batch`) |
| `wta-analyzer.service`, `wta-analyzer.timer` | Host systemd units |

Note on `renv`: the image restores `renv.lock` into `/opt/rlib` and installs the package from `R/` (no `.Rprofile`, no devtools), so the image has only the runtime packages.

## Security design

- **Salt** is a Docker secret (file mounted at `/run/secrets/wta_salt`), never in the image, an environment variable of the container, or git. Without it the job refuses to run and writes nothing.
- **Logs** are mounted read-only. The container has `network_mode: none`, a read-only root filesystem, all capabilities dropped, `no-new-privileges`, 1 GB memory limit, 1 CPU, 128 pids.
- **Output** goes only to `public/json/`, and only aggregates. Raw logs and hashes never leave `/var/log/website`.
- The geo databases (DB-IP Lite, CC BY 4.0) are optional and mounted read-only. Without them `country`/`asn` are NA.

## Server steps (Peter runs these himself)

1. **Copy the analyzer repo to the VPS** (no secrets in it; `data/` is not needed):
   ```bash
   # on your PC, from the project directory
   git -C WebsiteTrafficAnalyzer archive --format=tar.gz -o /tmp/wta-src.tar.gz HEAD
   scp /tmp/wta-src.tar.gz <your-admin-login>@<vps>:/tmp/
   ```
   (Once the work is merged, `git clone` on the VPS works too. `git archive` uses committed files, so commit or merge the `deploy/` files first.)
2. **Build the image** on the VPS:
   ```bash
   mkdir -p /root/wta-src && tar -xzf /tmp/wta-src.tar.gz -C /root/wta-src && rm /tmp/wta-src.tar.gz
   cd /root/wta-src
   docker build -f deploy/Dockerfile -t wta-analyzer:latest .
   docker image ls wta-analyzer          # about 1.4 GB on disk, see "Resources"
   df -h /                               # check you still have free space first
   ```
3. **Create the salt file.** Use the same salt as on your PC so hashes stay comparable between local and server runs. Copy it yourself over an authenticated channel; do not paste it into chat or tickets:
   ```bash
   # on your PC
   scp ~/.config/websitetrafficanalyzer/salt <your-admin-login>@<vps>:/tmp/wta_salt
   # on the VPS, as root
   install -d -m 700 /root/.config/wta
   install -m 400 -o 33 -g 33 /tmp/wta_salt /root/.config/wta/salt
   shred -u /tmp/wta_salt
   ```
   Owner uid 33 (www-data) is needed because the container runs as 33 and Docker mounts the file with its host permissions. Mode 400 keeps everybody else out.
4. **Optional geo databases**: put the DB-IP Lite country and ASN CSVs (`dbip-country-lite-*.csv.gz`, `dbip-asn-lite-*.csv.gz`) in `/root/.local/share/wta/geo` (mode 755 dir, 644 files). Without them, delete the `WTA_GEO_DIR` line and the `/geo` volume from the compose file.
5. **Add the compose override** and make the output directory writable by www-data:
   ```bash
   cp /root/wta-src/deploy/compose.kap60.yaml /root/personalWebsite/
   mkdir -p /root/personalWebsite/public/json
   chown 33:33 /root/personalWebsite/public/json    # or chmod 775 plus group 33
   ```
   Make sure `public/json/traffic.json` is in the website's `.gitignore` (it is) so the webhook `git pull` does not clash with it.
6. **Test run once by hand**:
   ```bash
   cd /root/personalWebsite
   time docker compose -f docker-compose.yaml -f compose.kap60.yaml run --rm analyzer
   ls -l public/json/traffic.json
   python3 -m json.tool public/json/traffic.json > /dev/null && echo valid
   grep -cE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' public/json/traffic.json    # must print 0
   ```
   The same command with `docker compose up` does **not** start the analyzer (profile `batch`).
7. **Enable the timer**:
   ```bash
   cp /root/wta-src/deploy/wta-analyzer.service /root/wta-src/deploy/wta-analyzer.timer /etc/systemd/system/
   systemctl daemon-reload
   systemctl enable --now wta-analyzer.timer
   systemctl list-timers wta-analyzer.timer
   ```
8. **Check results and failures**:
   ```bash
   journalctl -u wta-analyzer.service -n 30 --no-pager     # aggregate lines, elapsed time, memory, errors
   systemctl status wta-analyzer.service                   # "failed" after a bad night
   systemctl start wta-analyzer.service                    # run now, same as the timer
   ```
   A healthy run ends with `analyzer: done: wrote /out/traffic.json (...)`. A failure line starts with `analyzer: ERROR:` and the unit shows as failed (add a `OnFailure=` mail unit later if wanted).

### Update, disable, roll back

- **New analyzer version:** repeat step 1–2 (rebuild `wta-analyzer:latest`); the next run uses it. To keep the old one: `docker tag wta-analyzer:latest wta-analyzer:prev` before building, then retag to roll back.
- **Disable:** `systemctl disable --now wta-analyzer.timer`.
- **Remove completely:** disable, delete both unit files, `rm /root/personalWebsite/compose.kap60.yaml`, `docker image rm wta-analyzer:latest`, `shred -u /root/.config/wta/salt`.
- **Bad output:** the last good file is only replaced by a complete new one. To restore an older day, rerun after fixing the cause; no history of JSON files is kept (add a `cp` to a dated name if wanted).
- **Changing the salt** changes all `ip_hash` values; the dashboard's aggregates do not show hashes, but unique-visitor counts per day stay valid within one run.

## Resources (local test, 96,825 requests, 7–21 Oct 2026, ~16.5 MB of logs)

Measured on this PC with the same limits as in the compose file (`--memory 1g`, `--cpus 1`, no network, read-only root).

| | With geo databases | Without |
|---|---|---|
| Elapsed (read to JSON) | 11.9 s | 4.4 s |
| Peak memory (cgroup) | 623 MB | 188 MB |
| R peak (`gc()`) | 424 MB | 151 MB |
| Output | 21 KB | 21 KB |

- **Image size:** 1.39 GB on disk (of which about 1.36 GB is the `rocker/r-ver:4.6.1` base; our layers add about 30 MB; the base compresses to ~370 MB to download). The VPS was at 98% disk earlier, so check `df -h /` before the build, and run `docker image prune` / `docker builder prune` afterwards to drop build leftovers.
- **Memory:** ~0.6 GB with geo, in a 1 GB cap. Memory grows roughly linearly with the number of log lines (about 6 KB per request with geo). At 10x the traffic (1 M requests/week) the job would need about 6 GB and fail with an out-of-memory error; at that point switch to the chunked importer (`R/history.R`). Today's volume is far below that.
- **CPU:** one core for ~12 s a night, `Nice=10` and idle I/O class, so it will not disturb the website. The VPS timing will be slower on a shared vCPU; check the journal after the first run and update this table with the real numbers (LO10).
- **Logrotate:** the job reads every rotated file each night, so the window it covers is what logrotate retains. Nothing is deleted or modified.

## Known limits

- The local test ran on the PC, not on the VPS; VPS timings are still to be measured.
- `Persistent=true` plus a mid-rotation run could read `access.log` while Apache writes; the final partial line is dropped by the parser (it counts as unparsed, currently 0).
- Request totals are recomputed from all retained logs every night, so there is no incremental state to corrupt.
