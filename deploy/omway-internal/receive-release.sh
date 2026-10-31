#!/usr/bin/env bash
# Production deploy entry point. The CI deploy key is pinned to this script in
# /root/.ssh/authorized_keys on the production host:
#   command="/srv/election/deploy/receive-release.sh",restrict ssh-ed25519 AAAA... gitlab-ci
# so the key can do nothing else. The deploy:production job runs
#   tar -cz RELEASE_SHA backend deploy election_management/build/web | ssh root@<prod> <sha>
# Input is therefore only a 40-char sha (SSH_ORIGINAL_COMMAND) and a tarball on stdin.
set -euo pipefail

E=/srv/election
SHA=${SSH_ORIGINAL_COMMAND:-${1:-}}

die() { echo "receive-release: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root"
case "$SHA" in *[!0-9a-f]*|"") die "expected a commit sha, got: ${SHA:0:60}" ;; esac
[[ ${#SHA} -eq 40 ]] || die "commit sha must be 40 characters"

IN=$E/incoming/$SHA
rm -rf "$IN"
install -d -o root -g root -m 700 "$E/incoming" "$IN"
trap 'rm -rf "$IN"' EXIT

echo "== receive release $SHA"
# GNU tar refuses absolute paths and '..' members by default; --no-same-owner keeps
# everything root-owned until install-release.sh sets ownership explicitly.
tar -xz --no-same-owner --no-same-permissions -C "$IN"
[[ $(cat "$IN/RELEASE_SHA" 2>/dev/null) == "$SHA" ]] || die "RELEASE_SHA in the tarball does not match $SHA"
du -sh "$IN" | cut -f1 | sed 's/^/   size: /'

bash "$E/deploy/install-release.sh" "$IN" "$SHA"
