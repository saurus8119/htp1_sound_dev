#!/bin/bash
# tools/index.sh <release-tag> [archive-dir]
# Writes index.json using the exact release archive when present; it only packs locally
# when no archive was supplied. Call this AFTER the GitHub Release exists.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-}"
OUT="${2:-$ROOT/dist}"
[[ -n "$TAG" ]] || { echo "usage: tools/index.sh <release-tag> [archive-dir]" >&2; exit 2; }
REPO_URL=$(git -C "$ROOT" remote get-url origin | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##')
for PY in python3 python; do "$PY" -c pass >/dev/null 2>&1 && break; done
"$PY" - "$ROOT" "$OUT" "$TAG" "$REPO_URL" <<'PY'
import datetime, glob, hashlib, json, os, subprocess, sys
root, out, tag, repo = sys.argv[1:5]
addons = []
for mf in sorted(glob.glob(os.path.join(root, 'addons', '*', 'addon.json'))):
    m = json.load(open(mf))
    if not m.get('published', True):
        continue
    name = 'htp1-addon-%s-%s.tar.gz' % (m['id'], m['version'])
    path = os.path.join(out, name)
    if not os.path.isfile(path):
        subprocess.run(['bash', os.path.join(root, 'tools', 'pack.sh'), m['id'], out], check=True)
    # Ensure the tag and manifest agree; prevents a release URL to the wrong version.
    if tag != 'v' + m['version']:
        raise SystemExit('tag %s does not match %s version %s' % (tag, m['id'], m['version']))
    with open(path, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    entry = {k: m[k] for k in ('id', 'version', 'label', 'summary', 'requires') if k in m}
    entry['url'] = '%s/releases/download/%s/%s' % (repo, tag, name)
    entry['sha256'] = digest
    entry['size'] = os.path.getsize(path)
    addons.append(entry)
updated = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')
index = {'name': repo.rsplit('/', 1)[-1], 'updated': updated, 'addons': addons}
with open(os.path.join(root, 'index.json'), 'w', newline='\n') as f:
    json.dump(index, f, indent=2)
    f.write('\n')
print('index.json: %d addons, release %s' % (len(addons), tag))
PY
