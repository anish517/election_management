# Election Management System (Election Nepal)

Multi-tenant election platform. `backend/` is a Django REST API (`ems_backend` project, apps under `backend/apps/`). `election_management/` is the Flutter web client (Riverpod + go_router).

## Environments and branches

| Branch | Environment | URL | Host |
|---|---|---|---|
| `main` | development | https://election.omwaytechnologies.com | `omway-internal` (94.237.68.52) |
| `PRODUCTION` | production | https://electionnepal.org | `root@213.163.207.252` |

- Pushing `main` auto-deploys dev through GitLab CI. Check what is live with `cat /srv/election/DEPLOYED_SHA` on the host.
- To release to production, merge `main` into `PRODUCTION`. Don't force-push `PRODUCTION`.
- Both hosts use the same layout, `/srv/election/{app,venv,www,static,media,logs,run,backups,deploy}`, with systemd units `election-gunicorn`, `election-celery-worker` and `election-celery-beat`. Per-host names live in `/srv/election/site.conf`.
- Every deploy ends in `deploy/omway-internal/install-release.sh`. It runs pg_dump, syncs the code, swaps the Flutter build, runs migrate, restarts the services, runs a smoke test and writes `DEPLOYED_SHA`.

### Manual production release

CI `deploy:production` currently fails: `PROD_SSH_PRIVATE_KEY` isn't set, the CI key isn't in prod's authorized_keys, and `PRODUCTION` isn't a protected branch. Until those are fixed, release by hand from a clean export:

```sh
git archive <PRODUCTION sha> backend deploy election_management | tar -x -C <scratch>/release
cd <scratch>/release/election_management
~/fvm/versions/3.47.1/bin/flutter build web --release --no-wasm-dry-run \
  --dart-define=API_BASE_URL=https://electionnepal.org/v1
cd .. && echo <40-char sha> > RELEASE_SHA
tar -cz RELEASE_SHA backend deploy election_management/build/web | ssh -o BatchMode=yes root@213.163.207.252 /srv/election/deploy/receive-release.sh <40-char sha>
```

Keep the last line in exactly this shape: the local Claude permission rule matches it. Afterwards, check the live site over public HTTPS: `main.dart.js` should match the local build, `/` should return 200 and `/v1/auth/me/` should return 401.

Production sits behind Cloudflare in **Flexible** SSL mode. Don't add an HTTP to HTTPS redirect on the origin; it causes a redirect loop.

## Local development

- **Flutter:** use `~/fvm/versions/3.47.1/bin/flutter`, the same version as CI. The system Flutter is too old.
  - `pub get` regenerates the iOS/macOS Podfile and xcconfig files. Revert those changes; don't commit them.
- **Backend tests:** run `pytest` from `backend/`. Tests use in-memory SQLite.
  - `pip install` fails on psycopg2, so build a scratch venv from `backend/requirements.txt` without psycopg.
  - Stub Celery `.delay` calls in tests; there is no Redis.
- **Migrations:** commit them together with the model change, or CI's `check:migrations` fails.
- **Deploy scripts:** files in `deploy/omway-internal/` must be committed as executable (`git update-index --chmod=+x`).
- **Redis setting:** keep `USE_REDIS=False`. Setting it to True turns on DRF anonymous throttling, which locks out the kiosk and web-ballot endpoints.

## Backend conventions

- **Error format:** API errors use `{"error": {"code", "message", "field_errors"}}`. On the client, read them with `extractApiErrorMessage(e, fallback: ...)`.
- **Authentication:** `apps.core.authentication.SessionAwareJWTAuthentication` (simplejwt) rejects tokens issued before `user.tokens_valid_after`.
  - A password change or reset calls `user.end_other_sessions()`, and password change returns fresh `access`/`refresh` tokens.
- **Roles:** `super_admin` users have no organization (`User.save()` clears it). Only super admins create organizations, through the platform console.
- **Voting:** `cast_vote` locks the `VotingSession` and `VoterRoll` rows with `select_for_update` inside `transaction.atomic()`, so each voter casts exactly one vote. Keep it that way when touching voting code.
- **Candidate privacy:** use the helpers in `apps/candidates/models.py`: `limit_to_own_nomination`, `can_see_private_nomination`, `public_candidate_view` and `nomination_fee`.
  - During claims and objections (दाबी-विरोध), voters and candidates act on, and see, only their own name.
- **ID cards:** ID card URLs are signed links (`apps/core/id_card_links.py`). Don't make ID cards publicly fetchable by ID.

## Flutter conventions

- In `app_router.dart`, the router must `ref.read` its notifier and read `authProvider` inside `redirect`. Watching `authProvider` rebuilds GoRouter and resets navigation to `/login`.
- Theme: the colours live in `lib/core/theme/app_theme.dart`. The light page background is sky blue (`pageBackgroundLight`). Every screen must work in both light and dark mode, and text in input fields must stay readable in dark mode. The theme switch is `shared/widgets/theme_mode_button.dart`.
- The "Powered by Omway Technologies" footer is added app-wide in `main.dart`.
- After a deploy, blank icons are usually the browser or Cloudflare serving the old tree-shaken MaterialIcons font. Clear the cache before debugging.
