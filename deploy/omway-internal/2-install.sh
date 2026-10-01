#!/usr/bin/env bash
# Run as root on omway-internal after code is in /srv/election/app and this directory is
# in /srv/election/deploy. Idempotent: safe to re-run on every deploy.
set -euo pipefail
E=/srv/election
cd $E
[ -f app/manage.py ] || { echo "no code at $E/app"; exit 1; }
[ -f app/.env ]      || { echo "no .env — run 1-provision.sh first"; exit 1; }

echo "== venv + requirements (as omway)"
[ -x venv/bin/python ] || su omway -c "python3 -m venv $E/venv && $E/venv/bin/pip install -q --upgrade pip"
# requirements.txt is UTF-16 (BOM); pip decodes it.
su omway -c "$E/venv/bin/pip install -q -r $E/app/requirements.txt gunicorn"

echo "== assert settings inside the Python process"
su omway -c "cd $E/app && $E/venv/bin/python -c \"
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE','ems_backend.settings'); django.setup()
from django.conf import settings as s
d = s.DATABASES['default']
assert d['ENGINE'].endswith('postgresql') and d['NAME'] == 'election', d
assert s.DEBUG is False
assert s.SECURE_PROXY_SSL_HEADER, 'BEHIND_TLS_PROXY not set'
print('DB =', d['NAME'], '| DEBUG =', s.DEBUG, '| HOSTS =', s.ALLOWED_HOSTS, '| MEDIA =', s.MEDIA_ROOT)\""

echo "== migrate + collectstatic"
su omway -c "cd $E/app && $E/venv/bin/python manage.py migrate --noinput && $E/venv/bin/python manage.py collectstatic --noinput | tail -1"

echo "== systemd"
install -m 644 deploy/election-gunicorn.service deploy/election-celery-worker.service \
  deploy/election-celery-beat.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable -q election-gunicorn election-celery-worker election-celery-beat
systemctl restart election-gunicorn election-celery-worker election-celery-beat

echo "== nginx"
install -m 644 deploy/nginx-election-proxy.conf /etc/nginx/snippets/election-proxy.conf
if [ ! -e /etc/nginx/sites-available/election ]; then
  # First install only: afterwards certbot owns the 443 block in this file.
  install -m 644 deploy/nginx-election.conf /etc/nginx/sites-available/election
fi
ln -sfn /etc/nginx/sites-available/election /etc/nginx/sites-enabled/election
nginx -t && systemctl reload nginx

echo "== status"
sleep 2
systemctl is-active election-gunicorn election-celery-worker election-celery-beat redis-server nginx
ls -la $E/run/
free -m | sed -n 2p
