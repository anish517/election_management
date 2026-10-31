#!/usr/bin/env bash
# One-time setup of the PRODUCTION host (electionnepal.org, 213.163.207.252, Ubuntu 26.04,
# 1 vCPU / 842 MB RAM). Run as root from a copy of this directory, AFTER
# /srv/election/app/.env has been put in place (copied from development with the hostnames
# changed). Safe to re-run: every step checks before it changes anything.
#
# Deploys after this come from the PRODUCTION branch via CI (receive-release.sh), and use
# the shared scripts in deploy/omway-internal/.
set -euo pipefail
E=/srv/election
HERE=$(cd "$(dirname "$0")" && pwd)
SITE_HOST=electionnepal.org
SITE_SERVER_NAMES="electionnepal.org www.electionnepal.org"

[ -f $E/app/.env ] || { echo "put the production .env at $E/app/.env first"; exit 3; }

echo "== swap (842 MB RAM and none configured)"
if ! swapon --show --noheadings | grep -q .; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap -q /swapfile && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-election-swap.conf && sysctl -q -p /etc/sysctl.d/99-election-swap.conf
fi
swapon --show

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx postgresql redis-server certbot python3-certbot-nginx python3-venv rsync curl

echo "== user + layout"
id omway >/dev/null 2>&1 || useradd -m -s /bin/bash omway
# $E and $E/deploy are root-owned: the deploy scripts run as root.
install -d -o root  -g root  -m 755 $E $E/deploy
install -d -o omway -g omway -m 755 $E/app $E/www $E/media $E/static $E/logs $E/run $E/backups
chown omway:omway $E/app/.env && chmod 600 $E/app/.env
cat > $E/site.conf <<CONF
# Per-host settings read by deploy/omway-internal/{install-release,install-frontend,2-install}.sh
SITE_HOST=$SITE_HOST
SITE_SERVER_NAMES="$SITE_SERVER_NAMES"
CONF
chmod 644 $E/site.conf

echo "== redis: localhost only, small memory cap (Celery broker only)"
sed -i -E 's/^#? *maxmemory .*/maxmemory 64mb/' /etc/redis/redis.conf
grep -q '^maxmemory 64mb' /etc/redis/redis.conf || echo 'maxmemory 64mb' >> /etc/redis/redis.conf
grep -qE '^bind 127\.0\.0\.1( -::1)?$' /etc/redis/redis.conf || { echo "redis bind is not localhost-only; check /etc/redis/redis.conf"; exit 3; }
systemctl enable -q --now redis-server && systemctl restart redis-server

echo "== postgres: small-box tuning + role/database from .env"
PGCONF=$(ls -d /etc/postgresql/*/main | sort -V | tail -1)
cat > $PGCONF/conf.d/election.conf <<'PG'
# 842 MB RAM box shared with gunicorn + celery.
shared_buffers = 64MB
effective_cache_size = 256MB
work_mem = 4MB
maintenance_work_mem = 32MB
max_connections = 40
PG
systemctl restart postgresql
# Same credentials as development (.env is a copy); read them without printing.
eval "$(python3 - <<'PY'
import shlex, urllib.parse
for line in open('/srv/election/app/.env'):
    if line.startswith('DATABASE_URL='):
        u = urllib.parse.urlparse(line.split('=', 1)[1].strip())
        print(f"DBUSER={shlex.quote(u.username)} DBPASS={shlex.quote(urllib.parse.unquote(u.password))} DBNAME={shlex.quote(u.path.lstrip('/'))}")
PY
)"
[ "$DBNAME" = election ] && [ "$DBUSER" = election ] || { echo "unexpected DATABASE_URL in .env"; exit 3; }
if ! su postgres -c "psql -tAc \"select 1 from pg_roles where rolname='election'\"" | grep -q 1; then
  su postgres -c "psql -v ON_ERROR_STOP=1 -q" <<SQL
CREATE ROLE election LOGIN PASSWORD '$DBPASS';
ALTER ROLE election SET client_encoding TO 'utf8';
ALTER ROLE election SET default_transaction_isolation TO 'read committed';
ALTER ROLE election SET timezone TO 'UTC';
SQL
fi
su postgres -c "psql -tAc \"select 1 from pg_database where datname='election'\"" | grep -q 1 \
  || su postgres -c "createdb -O election -E UTF8 -T template0 election"
unset DBPASS
# Connectivity as omway is proven by 2-install.sh (settings assert + migrate).

echo "== celery: one worker process on this small box"
install -d /etc/systemd/system/election-celery-worker.service.d
cat > /etc/systemd/system/election-celery-worker.service.d/production.conf <<'UNIT'
[Service]
ExecStart=
ExecStart=/srv/election/venv/bin/celery -A ems_backend worker -l INFO \
    --concurrency=1 --max-tasks-per-child=200 \
    --logfile=/srv/election/logs/celery-worker.log
MemoryMax=256M
UNIT
systemctl daemon-reload

echo "== nginx: Cloudflare real IP, security headers, drop the default site"
install -m 644 $HERE/nginx-cloudflare-realip.conf /etc/nginx/conf.d/cloudflare-realip.conf
install -m 644 $HERE/nginx-security.conf /etc/nginx/conf.d/security.conf
rm -f /etc/nginx/sites-enabled/default
# Stock nginx.conf here has "server_tokens build;", which advertises the exact version.
sed -i -E 's/^(\s*)server_tokens\s+build;.*/\1server_tokens off;/' /etc/nginx/nginx.conf
nginx -t
systemctl enable -q --now nginx && systemctl reload nginx

echo "== done. Next: restore the database, copy media, first deploy (see README.md)"
free -m | sed -n 2,3p
