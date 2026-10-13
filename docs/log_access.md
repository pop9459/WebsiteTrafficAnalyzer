# Access to the server logs

The Apache logs of kapsiar.sk are persisted on the VPS in `/var/log/website` (`access.log`, `error.log` and the rotated `*.1`; mounted into the container as `/var/log/apache2`, see `docker-compose.yaml` of the website repo, KAP-49). `scripts/fetch_logs.sh` copies them to `data/raw/vps/`.

## Design: a read-only key that can run one command

- A dedicated user `logreader` (member of group `adm`, so it can read the logs) with its own SSH key (`~/.ssh/logreader_vps` locally).
- In the `logreader` user's `.ssh/authorized_keys` the key is restricted:
  ```
  restrict,command="/usr/local/bin/export-logs" ssh-ed25519 AAAA... claude-logpull
  ```
  `restrict` disables the shell, port forwarding and the like; `command=` makes every login run only the script, whatever the client asks for.
- `/usr/local/bin/export-logs` is three lines: `exec tar -czf - -C /var/log/website .` (a tarball of the log directory to stdout).
- The key can read the logs and nothing else: no shell, no write access, no other files.

The root key is not used for fetching. Only `scripts/fetch_logs.sh` needs to be allowed for Claude Code (permission rule `Bash(scripts/fetch_logs.sh)`).

## Usage

```bash
scripts/fetch_logs.sh
```

- Saves the tarball as `data/raw/vps/snapshots/logs_<UTC time>.tgz`. Snapshots are kept because the server rotates old logs away.
- Unpacks the newest snapshot into `data/raw/vps/`.
- `data/raw/` is git-ignored; raw logs are never committed or pasted anywhere.

The server address is not in the repository (the site is behind Cloudflare; the origin IP should stay private). Put it in `~/.config/websitetrafficanalyzer/vps_host` (one line) or set `WTA_VPS_HOST`. `WTA_VPS_KEY` overrides the key path. Host key checking is strict: if SSH reports a changed host key, stop and verify the server before reconnecting.

## Setup on a new server (once, as root)

1. Create the user `logreader` (`useradd --system --create-home --shell /bin/bash logreader`) and add it to the `adm` group (`usermod -aG adm logreader`).
2. Create `/usr/local/bin/export-logs` (mode 755) containing:
   ```sh
   #!/bin/sh
   exec tar -czf - -C /var/log/website .
   ```
3. Create `/home/logreader/.ssh` (mode 700, owner `logreader`) and put the restricted key line shown above in its `authorized_keys` (mode 600, owner `logreader`).
4. Test: `ssh -i ~/.ssh/logreader_vps -o IdentitiesOnly=yes logreader@<host> | tar -tzvf -` lists the log files.

## Revoking access

Remove the key line from the `logreader` user's `authorized_keys` (or delete the user) on the server.

## Limits

- Every fetch downloads the whole directory (a few MB). Fine for now; use `rsync` if the logs grow.
- Rotation keeps few generations (`access.log.1`), so fetch regularly. The history before 7 Oct 2026 is only in the manual backup of that day.
- The scheduled run on the VPS (KAP-60) will make the local copy unnecessary for the dashboard; it stays useful for development and labelling.
