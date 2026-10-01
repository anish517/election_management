#!/usr/bin/env bash
# Run as root on omway-internal, ONCE, before the first deploy.
# Installs Redis, creates /srv/election, the PostgreSQL role/database, and .env with
# generated secrets (never printed).
set -euo pipefail
E=/srv/election

if [ -e $E/app/.env ]; then
  echo "refusing: $E/app/.env already exists — already provisioned"; exit 3
fi

echo "== packages"
dpkg -s python3.12-venv >/dev/null 2>&1 || apt-get install -y -q python3.12-venv
dpkg -s redis-server    >/dev/null 2>&1 || apt-get install -y -q redis-server

echo "== redis: localhost only, small memory cap (Celery broker only)"
sed -i -E 's/^#? *maxmemory .*/maxmemory 64mb/' /etc/redis/redis.conf
grep -q '^maxmemory 64mb' /etc/redis/redis.conf || echo 'maxmemory 64mb' >> /etc/redis/redis.conf
grep -q '^bind 127.0.0.1 -::1' /etc/redis/redis.conf || { echo "redis bind is not localhost-only; check /etc/redis/redis.conf"; exit 3; }
systemctl enable -q --now redis-server
systemctl restart redis-server

echo "== layout (owned by omway, like the other apps in /srv)"
# $E and $E/deploy are root-owned: ci-deploy.sh in deploy/ runs as root via sudo.
install -d -o root  -g root  -m 755 $E $E/deploy
install -d -o omway -g omway -m 755 \
  $E/app $E/www $E/media $E/static $E/logs $E/run $E/backups

echo "== postgres role + database"
PW=$(openssl rand -hex 24)
if su postgres -c "psql -tAc \"select 1 from pg_roles where rolname='election'\"" | grep -q 1; then
  echo "refusing: role 'election' already exists"; exit 3
fi
su postgres -c "psql -v ON_ERROR_STOP=1 -q" <<SQL
CREATE ROLE election LOGIN PASSWORD '$PW';
CREATE DATABASE election OWNER election ENCODING 'UTF8' TEMPLATE template0;
ALTER ROLE election SET client_encoding TO 'utf8';
ALTER ROLE election SET default_transaction_isolation TO 'read committed';
ALTER ROLE election SET timezone TO 'UTC';
SQL

echo "== .env"
SK=$(openssl rand -hex 32)
umask 077
cat > $E/app/.env <<ENV
SECRET_KEY=$SK
DEBUG=False
ALLOWED_HOSTS=election.omwaytechnologies.com,127.0.0.1,localhost
CSRF_TRUSTED_ORIGINS=https://election.omwaytechnologies.com
BEHIND_TLS_PROXY=True
DATABASE_URL=postgres://election:$PW@127.0.0.1:5432/election
STATIC_ROOT=$E/static
MEDIA_ROOT=$E/media
FRONTEND_URL=https://election.omwaytechnologies.com

# Redis is the Celery broker only. USE_REDIS stays False on purpose: True also turns on
# DRF's 10/min anon throttle, which would lock out kiosk/web-ballot (AllowAny) endpoints.
# nginx rate-limits instead.
USE_REDIS=False
REDIS_URL=redis://127.0.0.1:6379/1
CELERY_BROKER_URL=redis://127.0.0.1:6379/1
CELERY_RESULT_BACKEND=redis://127.0.0.1:6379/1

JWT_ACCESS_TOKEN_LIFETIME_MINUTES=15
JWT_REFRESH_TOKEN_LIFETIME_DAYS=30

# Fill these in for OTP/notification delivery, then: systemctl restart election-gunicorn election-celery-worker
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
DEFAULT_FROM_EMAIL=
SPARROW_SMS_TOKEN=
SPARROW_SMS_FROM=SparrowSMS
FCM_SERVER_KEY=
ENV
chown omway:omway $E/app/.env

echo "== verify: omway connects with the generated credentials"
su omway -c "PGPASSWORD='$PW' psql -h 127.0.0.1 -U election -d election -tAc \"select current_user || ' @ ' || current_database()\""
echo "== done. Next: deploy.sh from a workstation (or 2-install.sh here once code is in place)"
