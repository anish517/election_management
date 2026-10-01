#!/usr/bin/env bash
# Run from a workstation at the repo root:  deploy/omway-internal/deploy.sh
# Builds the Flutter web bundle, uploads backend/ + deploy/ + the bundle to omway-internal,
# backs up the database, then runs 2-install.sh. Needs Flutter with Dart >= 3.12.
set -euo pipefail
HOST=${HOST:-omway-internal}
E=/srv/election
API_BASE_URL=${API_BASE_URL:-https://election.omwaytechnologies.com/v1}
cd "$(git rev-parse --show-toplevel)"

if [ "${SKIP_FLUTTER:-0}" != 1 ]; then
  echo "== flutter build web ($API_BASE_URL)"
  (cd election_management && flutter pub get && \
    flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL")
fi
[ -f election_management/build/web/index.html ] || { echo "no Flutter build"; exit 1; }

echo "== pg_dump before migrate"
ssh "$HOST" "cd $E/app && [ -x $E/venv/bin/python ] && eval \"\$(runuser -u omway -- $E/venv/bin/python -c \"
import shlex, dj_database_url; from decouple import config
u = dj_database_url.parse(config('DATABASE_URL'))
print(' '.join(f'export {e}={shlex.quote(str(u[k]))};' for e, k in (('PGHOST','HOST'),('PGUSER','USER'),('PGPASSWORD','PASSWORD'),('PGDATABASE','NAME'))))
\")\" && runuser -u omway --preserve-environment -- pg_dump -Fc --no-owner -f $E/backups/pre-deploy-\$(date +%F-%H%M%S).dump \
  && ls -1t $E/backups/pre-deploy-*.dump | tail -n +15 | xargs -r rm -- || echo '(no venv yet, skipping backup)'"

echo "== sync"
# .env is server-only; excluding it also protects it from --delete.
rsync -az --delete \
  --exclude='/.env' --exclude='__pycache__/' --exclude='*.pyc' --exclude='/media/' \
  --exclude='/staticfiles/' --exclude='*.sqlite3' --exclude='*.db' \
  backend/ "$HOST:$E/app/"
rsync -az --delete deploy/omway-internal/ "$HOST:$E/deploy/"
rsync -az --delete election_management/build/web/ "$HOST:$E/www/"
# macOS openrsync has no --chown.
ssh "$HOST" "chown -R omway:omway $E/app $E/www"
git rev-parse HEAD | ssh "$HOST" "cat > $E/DEPLOYED_SHA"

echo "== install"
ssh "$HOST" "bash $E/deploy/2-install.sh"
