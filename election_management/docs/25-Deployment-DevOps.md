# 25. Deployment & DevOps

## 25.1 Environments

| Environment | Purpose | Infra |
|---|---|---|
| Local | Development | Docker Compose (Postgres, Redis, Django, Celery all containerized) |
| Staging | Pre-release validation, demo environment for prospective orgs | Render/Railway, scaled-down |
| Production | Live | Render/Railway initially → AWS/GCP migration path at scale |

## 25.2 Containerization

```dockerfile
# Simplified illustrative Dockerfile shape
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN python manage.py collectstatic --noinput
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "ems.asgi:application"]
```

Separate images/services from the same codebase:
- `web` — Gunicorn/Uvicorn (ASGI, for Channels support)
- `worker` — Celery worker
- `beat` — Celery beat scheduler
- `migrate` — one-off migration job run on deploy

## 25.3 Render Deployment Notes

Building on the deployment pattern already validated for the cooperative-management backend:

- `render.yaml` defines all four services (web, worker, beat, Postgres) as a single blueprint.
- `build.sh` runs `pip install`, `collectstatic`, and `migrate` on deploy.
- **`CSRF_TRUSTED_ORIGINS`** and `ALLOWED_HOSTS` must explicitly include the Render-assigned domain and any custom domain — a previously-hit gap in earlier deployment work, called out here so it isn't missed again.
- Environment variables (secrets) managed via Render's environment group, never committed to the repo.

## 25.4 CI/CD Pipeline (GitHub Actions)

```
on: push to main / PR
  1. Lint (ruff/flake8) + format check (black)
  2. Run test suite (see 26-Testing-Strategy.md) with coverage gate
  3. Dependency vulnerability scan (Dependabot/pip-audit)
  4. Build Docker image, push to registry (on main only)
  5. Deploy to staging (auto, on main)
  6. Deploy to production (manual approval gate)
```

## 25.5 Database Migrations

- Migrations reviewed in PR alongside model changes — no direct schema edits against production.
- Backward-compatible migration pattern for zero-downtime deploys (add-column-nullable → backfill → make-non-nullable in a follow-up deploy, rather than a single breaking migration) for any change to a high-traffic table (`votes`, `voter_rolls`).

## 25.6 Monitoring & Alerting

| What | Tool | Alert Threshold (illustrative) |
|---|---|---|
| Application errors | Sentry (or similar) | Any 500-level spike |
| Uptime | External uptime checker | Any downtime during an active voting window → immediate page |
| Celery queue depth | Flower / custom metric | Queue depth > threshold → possible backlog risk to time-sensitive state transitions |
| Database performance | Managed provider dashboard + slow query log | Query time regression on `votes`/`voter_rolls` tables specifically |
| Notification delivery failure rate | Custom dashboard from `notifications` table | Failure rate > 5% on any channel |

## 25.7 Backups & Disaster Recovery

- Automated daily PostgreSQL backups (managed provider), retained per the org data-retention policy at minimum, with point-in-time recovery enabled.
- **Backup restore drills**: performed on a schedule (e.g., quarterly) against a staging environment to confirm backups are actually restorable, not just taken.
- RPO target: < 1 hour (via WAL-based point-in-time recovery). RTO target: < 4 hours for full service restoration.

## 25.8 Scaling Considerations

- Web/API layer: horizontally scalable (stateless, JWT-based auth — no server-side session affinity required).
- Database: read replicas for reporting/analytics queries (§18) to keep heavy report generation off the primary write path used by active voting.
- A single high-turnout election (e.g., a large cooperative's AGM, thousands of voters in a tight voting window) is the platform's peak-load scenario — load testing (§26) specifically targets this pattern, not steady-state average load.

Continue to `26-Testing-Strategy.md`.
