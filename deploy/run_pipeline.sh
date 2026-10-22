#!/bin/sh
# Entry point of the analyzer container (KAP-60).
# Reads the salt from a secret file, runs pipeline.R, keeps the previous
# traffic.json if anything fails. Prints aggregate lines only, never log lines.
set -eu

SALT_FILE="${WTA_SALT_FILE:-/run/secrets/wta_salt}"
LOG_DIR="${WTA_LOG_DIR:-/logs}"
OUT_FILE="${WTA_OUT_FILE:-/out/traffic.json}"
TMP_FILE="${OUT_FILE}.tmp"

log() { printf '%s analyzer: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
fail() { log "ERROR: $*"; rm -f "$TMP_FILE"; exit 1; }

[ -r "$SALT_FILE" ] || fail "salt secret not readable at $SALT_FILE (see docs/deploy.md); nothing written"
[ -s "$SALT_FILE" ] || fail "salt secret at $SALT_FILE is empty; nothing written"
[ -d "$LOG_DIR" ]   || fail "log directory $LOG_DIR not mounted; nothing written"
[ -w "$(dirname "$OUT_FILE")" ] || fail "output directory $(dirname "$OUT_FILE") is not writable by uid $(id -u)"

if [ -n "${WTA_GEO_DIR:-}" ] && [ ! -d "$WTA_GEO_DIR" ]; then
  log "WARNING: WTA_GEO_DIR=$WTA_GEO_DIR not mounted; country/ASN fields will be NA"
  unset WTA_GEO_DIR
fi
[ -n "${WTA_GEO_DIR:-}" ] || log "no geo databases configured; country/ASN fields will be NA"

# The salt goes to R through the environment of this one process only.
WTA_SALT="$(head -n 1 "$SALT_FILE" | tr -d '\r\n')"
export WTA_SALT WTA_LOG_DIR="$LOG_DIR" WTA_OUT_FILE="$OUT_FILE" WTA_TMP_FILE="$TMP_FILE"
rm -f "$TMP_FILE"

log "start"
if ! Rscript --vanilla /app/pipeline.R; then
  fail "pipeline.R failed; previous $(basename "$OUT_FILE") kept"
fi
[ -s "$TMP_FILE" ] || fail "pipeline produced no output; previous $(basename "$OUT_FILE") kept"
mv -f "$TMP_FILE" "$OUT_FILE"
log "done: wrote $OUT_FILE ($(wc -c < "$OUT_FILE") bytes)"
