#!/usr/bin/env bash
# Development deploy entry point (omway-internal). Called by the GitLab deploy job as
#   sudo /srv/election/deploy/ci-deploy.sh "$CI_PROJECT_DIR" "$CI_COMMIT_SHA"
# (allowed by /etc/sudoers.d/gitlab-runner-election). Checks that the argument is the
# runner's clean checkout of exactly that commit, then hands it to install-release.sh.
set -euo pipefail

SRC=${1:?usage: ci-deploy.sh <checkout-dir> <commit-sha>}
SHA=${2:?usage: ci-deploy.sh <checkout-dir> <commit-sha>}
E=/srv/election
BUILDS=/home/gitlab-runner/builds

die() { echo "ci-deploy: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (via sudo)"
case "$SHA" in *[!0-9a-f]*|"") die "commit sha is not hex: $SHA" ;; esac
[[ ${#SHA} -eq 40 ]] || die "commit sha must be 40 characters"
SRC=$(realpath -e -- "$SRC") || die "checkout dir does not exist"
[[ $SRC == "$BUILDS"/* ]] || die "checkout must live under $BUILDS, got $SRC"
HEAD=$(git -C "$SRC" rev-parse HEAD) || die "not a git checkout"
[[ $HEAD == "$SHA" ]] || die "checkout is at $HEAD, pipeline is for $SHA"
git -C "$SRC" diff --quiet HEAD -- backend deploy || die "tracked files in the checkout are modified"
git -C "$SRC" --no-pager log --oneline -1

# The installed copy, not the checkout's: what runs as root is only ever what a previous
# deploy put in the root-owned deploy/ directory.
exec bash "$E/deploy/install-release.sh" "$SRC" "$SHA"
