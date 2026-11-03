#!/bin/bash
# Forward AirPlay volume to the HTP-1 rather than attenuating audio in software.
VOL="${1:-}"
[[ "$VOL" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || exit 0
if awk "BEGIN { exit !($VOL <= -144) }"; then
  exec /opt/olympia/addon-source mute airplay
fi
exec /opt/olympia/addon-source volume airplay "$(awk "BEGIN { f = ($VOL + 30) / 30; if (f < 0) f = 0; if (f > 1) f = 1; printf \"%.4f\", f }")"
