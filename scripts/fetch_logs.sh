#!/usr/bin/env bash
# Fetch the Apache logs of kapsiar.sk from the VPS into data/raw/vps/.
#
# Usage (from anywhere):
#   scripts/fetch_logs.sh
#
# Uses a dedicated read-only key. On the server that key can run exactly one
# command (/usr/local/bin/export-logs, which streams /var/log/website as a
# tarball); it has no shell and cannot write. Setup: docs/log_access.md.
#
# Each run saves the tarball under data/raw/vps/snapshots/ (kept, because the
# server rotates old logs away) and unpacks the newest one into data/raw/vps/.
# Nothing is printed from the logs. data/raw/ is git-ignored.

set -euo pipefail

# The origin address is not committed: the site is behind Cloudflare, and the
# origin IP should not be public. Set WTA_VPS_HOST or write it into the file.
config="$HOME/.config/websitetrafficanalyzer"
host="${WTA_VPS_HOST:-}"
if [ -z "$host" ] && [ -f "$config/vps_host" ]; then
  host="$(head -n 1 "$config/vps_host")"
fi
if [ -z "$host" ]; then
  echo "No VPS host: set WTA_VPS_HOST or write it into $config/vps_host" >&2
  exit 1
fi
key="${WTA_VPS_KEY:-$HOME/.ssh/logreader_vps}"

cd "$(dirname "$0")/.."
dest="data/raw/vps"
mkdir -p "$dest/snapshots"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
snapshot="$dest/snapshots/logs_$stamp.tgz"

ssh -i "$key" \
  -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o ConnectTimeout=15 \
  "logreader@$host" > "$snapshot.part"

# Refuse an empty or corrupt download before it replaces anything.
tar -tzf "$snapshot.part" > /dev/null
mv "$snapshot.part" "$snapshot"

tar -xzf "$snapshot" -C "$dest" --no-same-owner
echo "Saved $snapshot ($(du -h "$snapshot" | cut -f1))"
echo "Unpacked into $dest/:"
ls -l "$dest" | awk 'NR > 1 && $NF != "snapshots" {printf "  %s  %s bytes\n", $NF, $5}'
