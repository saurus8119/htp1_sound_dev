#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-"$HERE/build-output"}
mkdir -p "$OUT" "$OUT/work"
docker build --platform linux/arm/v7 -t htp1-airplay-build "$HERE"
docker run --rm --platform linux/arm/v7 -v "$OUT:/out" -v "$OUT/work:/work" htp1-airplay-build
