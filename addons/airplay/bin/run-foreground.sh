#!/bin/bash
# Diagnostic foreground runner. Stop airplay.service before using this script.
if systemctl is-active --quiet airplay.service; then
  echo "Stop airplay.service before running this helper." >&2
  exit 1
fi
NAME="$(tr -d '\000-\037' < /var/lib/olympia/unitname.txt 2>/dev/null)"
[ -n "$NAME" ] || NAME="HTP-1"
exec /var/lib/olympia/addons/airplay/bin/shairport-sync \
  --configfile=/var/lib/olympia/addons/airplay/etc/shairport-sync.conf -a "$NAME"
