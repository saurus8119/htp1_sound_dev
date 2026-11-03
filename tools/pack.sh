#!/bin/bash
# tools/pack.sh <id> [outdir]
#   Finds the source directory by matching the add-on manifest ID.
# tools/pack.sh <source-dir> <package-id> <outdir>
#   Explicitly separates the source directory from the packaged add-on ID.
# Builds the installable tarball only. Diagnostics are deliberately kept out of it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -ge 3 ]]; then
    SRC_ARG="$1"
    ID="$2"
    OUT="$3"
    case "$SRC_ARG" in
        /*) SRC="$SRC_ARG" ;;
        *)  SRC="$ROOT/$SRC_ARG" ;;
    esac
else
    ID="${1:-}"
    OUT="${2:-$ROOT/dist}"
    SRC=""
fi

[[ -n "${ID:-}" ]] || {
    echo "usage: tools/pack.sh <id> [outdir]" >&2
    echo "   or: tools/pack.sh <source-dir> <package-id> <outdir>" >&2
    exit 2
}

for PY in python3 python; do
    if "$PY" -c pass >/dev/null 2>&1; then
        break
    fi
done
command -v "$PY" >/dev/null 2>&1 || {
    echo "pack: Python is required" >&2
    exit 1
}

# Legacy mode: locate the source directory by manifest ID.
# This supports an ID such as airplay2 while the source remains addons/airplay.
if [[ -z "$SRC" ]]; then
    for manifest in "$ROOT"/addons/*/addon.json; do
        [[ -f "$manifest" ]] || continue
        if "$PY" - "$manifest" "$ID" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    manifest = json.load(f)

sys.exit(0 if manifest.get("id") == sys.argv[2] else 1)
PY
        then
            SRC="${manifest%/addon.json}"
            break
        fi
    done
fi

[[ -n "$SRC" && -f "$SRC/addon.json" ]] || {
    echo "pack: no addon.json found for package ID '$ID' (source: ${SRC:-not found})" >&2
    exit 1
}

mkdir -p "$OUT"

NAME=$("$PY" - "$SRC" "$ID" "$OUT" <<'PY'
import gzip
import json
import os
import sys
import tarfile

src, aid, out = sys.argv[1:4]

with open(os.path.join(src, "addon.json"), encoding="utf-8") as f:
    manifest = json.load(f)

if manifest.get("id") != aid:
    raise SystemExit(
        "pack: manifest ID %r does not match package ID %r"
        % (manifest.get("id"), aid)
    )

version = manifest.get("version")
if not isinstance(version, str) or not version:
    raise SystemExit("pack: manifest has no valid version")

declared_units = manifest.get("units", {})
if not isinstance(declared_units, dict):
    raise SystemExit("pack: manifest 'units' must be an object")

name = "htp1-addon-%s-%s.tar.gz" % (aid, version)
ship_files = {"addon.json", "README.md"}
# lib/ is included because this build bundles libplist-2.0.so for the target.
ship_dirs = {"bin", "etc", "units", "debs", "flows", "www", "hooks", "lib"}
path = os.path.join(out, name)

with open(path, "wb") as raw:
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w") as tar:
            for root, dirs, files in os.walk(src):
                rel = os.path.relpath(root, src).replace(os.sep, "/")

                if rel == ".":
                    dirs[:] = sorted(d for d in dirs if d in ship_dirs)
                    files = [f for f in files if f in ship_files]
                elif rel == "units":
                    # Source trees may retain legacy units; only package units
                    # explicitly registered by this add-on's manifest.
                    files = [f for f in files if f in declared_units]
                    dirs.sort()
                else:
                    dirs.sort()

                top = rel.split("/")[0] if rel != "." else ""

                for directory in dirs:
                    arcname = aid + "/" + (
                        directory if rel == "." else rel + "/" + directory
                    )
                    info = tarfile.TarInfo(arcname)
                    info.type = tarfile.DIRTYPE
                    info.mode = 0o755
                    info.uid = info.gid = 0
                    info.uname = info.gname = "root"
                    info.mtime = 0
                    tar.addfile(info)

                for filename in sorted(files):
                    file_path = os.path.join(root, filename)
                    arcname = aid + "/" + (
                        filename if rel == "." else rel + "/" + filename
                    )
                    info = tar.gettarinfo(file_path, arcname)
                    info.uid = info.gid = 0
                    info.uname = info.gname = "root"
                    info.mtime = 0
                    info.mode = 0o755 if top in ("bin", "hooks") else 0o644

                    with open(file_path, "rb") as source:
                        tar.addfile(info, source)

print(name)
PY
)

(
    cd "$OUT"
    sha256sum "$NAME" > "$NAME.sha256"
)

echo "$OUT/$NAME"
