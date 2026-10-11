#!/usr/bin/env bash
# Deploys one commit to this host. Called by the GitLab deploy job as
#   sudo /srv/election/deploy/ci-deploy.sh "$CI_PROJECT_DIR" "$CI_COMMIT_SHA"
# (allowed by /etc/sudoers.d/gitlab-runner-election). Steps: validate args, pg_dump,
# rsync backend/ and deploy/, optional Flutter bundle, 2-install.sh, smoke test.
# Transcript: /srv/election/logs/deploy-<timestamp>.log
set -euo pipefail

SRC=${1:?usage: ci-deploy.sh <checkout-dir> <commit-sha>}
SHA=${2:?usage: ci-deploy.sh <checkout-dir> <commit-sha>}
E=/srv/election
BUILDS=/home/gitlab-runner/builds
KEEP_DUMPS=14
HOSTNAME_=election.omwaytechnologies.com

die() { echo "ci-deploy: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (via sudo)"
case "$SHA" in *[!0-9a-f]*|"") die "commit sha is not hex: $SHA" ;; esac
[[ ${#SHA} -eq 40 ]] || die "commit sha must be 40 characters"
SRC=$(realpath -e -- "$SRC") || die "checkout dir does not exist"
[[ $SRC == "$BUILDS"/* ]] || die "checkout must live under $BUILDS, got $SRC"
[[ -f $SRC/backend/manage.py ]] || die "no backend/manage.py in $SRC"
[[ -f $SRC/deploy/omway-internal/2-install.sh ]] || die "no deploy/omway-internal in $SRC"
HEAD=$(git -C "$SRC" rev-parse HEAD) || die "not a git checkout"
[[ $HEAD == "$SHA" ]] || die "checkout is at $HEAD, pipeline is for $SHA"
git -C "$SRC" diff --quiet HEAD -- backend deploy || die "tracked files in the checkout are modified"

TS=$(date +%Y-%m-%d-%H%M%S)
mkdir -p "$E/logs"
exec > >(tee -a "$E/logs/deploy-$TS.log") 2>&1
echo "== deploy $SHA at $TS from $SRC"
git -C "$SRC" --no-pager log --oneline -1

echo "== pg_dump before migrate"
# DATABASE_URL from .env -> libpq env vars, so the password never appears in argv.
eval "$(runuser -u omway -- env -C "$E/app" "$E/venv/bin/python" - <<'PY'
import shlex
import dj_database_url
from decouple import config
u = dj_database_url.parse(config("DATABASE_URL"))
for env, key in (("PGHOST", "HOST"), ("PGPORT", "PORT"), ("PGUSER", "USER"),
                 ("PGPASSWORD", "PASSWORD"), ("PGDATABASE", "NAME")):
    if u.get(key):
        print(f"export {env}={shlex.quote(str(u[key]))}")
PY
)"
DUMP="$E/backups/pre-deploy-$TS-${SHA:0:7}.dump"
runuser -u omway --preserve-environment -- pg_dump --format=custom --no-owner --file="$DUMP"
unset PGPASSWORD
ls -la "$DUMP"
ls -1t "$E"/backups/pre-deploy-*.dump 2>/dev/null | tail -n +$((KEEP_DUMPS + 1)) | xargs -r rm -v --

# .env is the only server-only file in app/; excluding it also protects it from --delete.
# --checksum: CI checkouts have fresh mtimes.
echo "== sync backend/ -> $E/app (changed files only)"
rsync -a --checksum --delete --chown=omway:omway --info=name,del \
    --exclude='/.env' --exclude='__pycache__/' --exclude='*.pyc' \
    --exclude='/media/' --exclude='/staticfiles/' --exclude='*.sqlite3' --exclude='*.db' \
    "$SRC/backend/" "$E/app/"

# deploy/ is root-owned: this script runs as root via sudo, so nothing else may write here.
echo "== sync deploy/omway-internal/ -> $E/deploy"
rsync -a --checksum --delete --chown=root:root --info=name,del --exclude='__pycache__/' \
    "$SRC/deploy/omway-internal/" "$E/deploy/"
chown root:root "$E/deploy" && chmod 755 "$E/deploy"
# Keep the sudo target executable and nothing in deploy/ group/world-writable, whatever
# mode git or the runner's umask gave the files.
chmod 644 "$E"/deploy/* && chmod 755 "$E"/deploy/*.sh

WEB=$SRC/election_management/build/web
if [[ -f $WEB/index.html ]]; then
    bash "$E/deploy/install-frontend.sh" "$WEB"
else
    echo "== no election_management/build/web in the checkout; Flutter bundle left as is"
fi

bash "$E/deploy/2-install.sh"

echo "== smoke test (local, via nginx)"
check() {  # check <want> <path>
    local code
    code=$(curl -sk -o /dev/null -w '%{http_code}' --resolve "$HOSTNAME_:443:127.0.0.1" "https://$HOSTNAME_$2")
    echo "   $2 -> $code (want $1)"
    [[ $code == "$1" ]]
}
for _ in 1 2 3 4 5; do check 401 /v1/auth/me/ >/dev/null 2>&1 && break; sleep 2; done
check 200 / && check 401 /v1/auth/me/ && check 200 /admin/login/ \
    || { journalctl -u election-gunicorn -n 30 --no-pager; die "smoke test failed"; }

echo "$SHA" > "$E/DEPLOYED_SHA"
echo "== deployed $SHA OK"
