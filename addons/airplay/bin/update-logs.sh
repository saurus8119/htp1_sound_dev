#!/bin/sh
# Publish only HTPlay-1's own systemd journal entries for its local logs page.
set -eu

ADDON_DIR="/var/lib/olympia/addons/airplay2"
WWW_DIR="$ADDON_DIR/www"
LOG_FILE="$WWW_DIR/logs.txt"
TMP_FILE="$WWW_DIR/.logs.txt.tmp"

mkdir -p "$WWW_DIR"

if ! command -v journalctl >/dev/null 2>&1; then
    printf '%s\n' 'journalctl is not available on this HTP-1.' > "$TMP_FILE"
else
    journalctl --no-pager --quiet -o short-iso -n 300 \
        -u airplay2.service -u nqptp-airplay2.service > "$TMP_FILE" 2>&1 || true
    if [ ! -s "$TMP_FILE" ]; then
        printf '%s\n' 'No HTPlay-1 journal entries yet.' > "$TMP_FILE"
    fi
fi

chmod 0644 "$TMP_FILE"
mv -f "$TMP_FILE" "$LOG_FILE"
