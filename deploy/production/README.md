# Production host — electionnepal.org

`213.163.207.252` (UpCloud sg-sin1, Ubuntu 26.04, 1 vCPU, 842 MB RAM + 2 GB swap).
Same layout and services as development (`/srv/election`, `election-gunicorn`,
`election-celery-worker`, `election-celery-beat`, Postgres `election`, Redis as the
Celery broker), installed by the shared scripts in `deploy/omway-internal/`.
Per-host settings are in `/srv/election/site.conf` (`SITE_HOST`, `SITE_SERVER_NAMES`).

Differences from development:

- One Celery worker process (systemd drop-in `election-celery-worker.service.d/production.conf`).
- Postgres tuned for the small box (`/etc/postgresql/*/main/conf.d/election.conf`).
- No GitLab runner. CI deploys by streaming a tarball over SSH; the CI key in
  `/root/.ssh/authorized_keys` is pinned with
  `command="/srv/election/deploy/receive-release.sh",restrict`.

## Releasing

Push (or merge `main`) to the protected `PRODUCTION` branch. The pipeline builds the
Flutter bundle for `https://electionnepal.org/v1` and runs `deploy:production`, which
backs up the database before migrating.

## Initial setup (done 2026-10-31)

1. `.env` copied from development; only `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS` and
   `FRONTEND_URL` changed. `SECRET_KEY`, DB password and mail settings are the same.
2. `provision.sh` (this directory) as root.
3. Database: `pg_dump -Fc --no-owner --no-acl` on development, `pg_restore --no-owner
   --no-acl --role=election` here. Media: tar of `/srv/election/media`.
4. First release through `receive-release.sh`, then
   `certbot --nginx -d electionnepal.org -d www.electionnepal.org --redirect`.
5. Cloudflare for electionnepal.org was in **Flexible** SSL mode (it reaches the origin
   over HTTP), so certbot's HTTP->HTTPS redirect looped. The certbot redirect block was
   removed from `/etc/nginx/sites-available/election` and the main server block also
   listens on 80 (backup of certbot's version: `/root/nginx-election.certbot.bak`).
   Once the zone is set to **Full (strict)**, traffic uses the 443 listener and the
   port-80 listener only matters for direct-to-origin requests.
