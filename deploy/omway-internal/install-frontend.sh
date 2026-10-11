#!/usr/bin/env bash
# Installs a Flutter web build into /srv/election/www (atomic swap, previous kept at
# www.prev). Run as root:  install-frontend.sh <dir containing index.html>
set -euo pipefail
SRC=${1:?usage: install-frontend.sh <build-dir>}
E=/srv/election
[[ -f $SRC/index.html && -f $SRC/main.dart.js ]] || { echo "install-frontend: $SRC is not a Flutter web build" >&2; exit 1; }
grep -q 'election.omwaytechnologies.com/v1' "$SRC/main.dart.js" \
    || { echo "install-frontend: bundle does not reference election.omwaytechnologies.com/v1 — built without --dart-define=API_BASE_URL?" >&2; exit 1; }

echo "== install Flutter bundle -> $E/www"
rm -rf "$E/www.next"
rsync -a --chown=omway:omway "$SRC/" "$E/www.next/"
rm -rf "$E/www.prev"
[[ -d $E/www ]] && mv "$E/www" "$E/www.prev"
mv "$E/www.next" "$E/www"
du -sh "$E/www" | cut -f1 | sed 's/^/   size: /'
