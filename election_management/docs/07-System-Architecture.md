# 07. System Architecture

## 7.1 High-Level Architecture

```
                         ┌─────────────────────────────┐
                         │        Flutter Apps          │
                         │  Voter | Candidate | Admin    │
                         │  (Android, iOS, Web)          │
                         └───────────────┬───────────────┘
                                          │ HTTPS (REST) + WSS (live dashboard)
                                          ▼
                         ┌─────────────────────────────┐
                         │        Nginx (reverse proxy) │
                         │        TLS termination        │
                         └───────────────┬───────────────┘
                                          ▼
                ┌─────────────────────────────────────────────┐
                │           Django REST Framework API           │
                │  ┌───────────┐ ┌───────────┐ ┌─────────────┐ │
                │  │  Auth &   │ │  Core      │ │  Django      │ │
                │  │  RBAC     │ │  Domain    │ │  Channels     │ │
                │  │  (JWT)    │ │  ViewSets  │ │  (WebSocket)  │ │
                │  └───────────┘ └───────────┘ └─────────────┘ │
                └───────┬─────────────┬──────────────┬─────────┘
                        │             │              │
             ┌──────────▼───┐  ┌──────▼─────┐  ┌─────▼──────┐
             │  PostgreSQL   │  │  Redis      │  │  Celery     │
             │  (primary DB) │  │  (cache +   │  │  Workers    │
             │               │  │  channel    │  │  (async     │
             │               │  │  layer)     │  │  jobs)      │
             └───────────────┘  └────────────┘  └─────┬──────┘
                                                        │
                       ┌────────────────────────────────┼───────────────────┐
                       ▼                                ▼                   ▼
             ┌─────────────────┐              ┌─────────────────┐ ┌──────────────────┐
             │  File Storage     │              │  Notification    │ │  Payment Gateways  │
             │  (S3 / Cloudinary)│              │  Gateways (FCM,  │ │  (Khalti, eSewa,   │
             │                   │              │  Sparrow SMS,    │ │  Stripe)           │
             │                   │              │  SMTP)           │ │                    │
             └───────────────────┘              └─────────────────┘ └────────────────────┘
```

## 7.2 Architectural Style

- **Modular monolith**, not microservices, for v1. A single Django project with clearly bounded apps (`organizations`, `members`, `elections`, `candidates`, `voting`, `results`, `audit`, `notifications`, `billing`) — each with its own models, serializers, views, and permission classes.
- **Why not microservices at this stage**: team size, deployment simplicity, and the fact that most of these modules share the same transactional boundary (an election's state machine touches candidates, votes, and results together — splitting these into separate services would introduce distributed-transaction complexity with no corresponding scale benefit at this stage).
- **Microservice-ready boundary already drawn**: because Django apps are cleanly separated with their own models and a thin cross-app interface (service functions, not raw ORM queries across app boundaries), the `voting` app in particular could be extracted into its own service later if the vote-tallying workload needs independent scaling.

## 7.3 Multi-Tenancy Model

**Shared database, shared schema, tenant-scoped rows** (not schema-per-tenant, not database-per-tenant):

- Every tenant-scoped model has a non-nullable `organization = models.ForeignKey(Organization)`.
- A custom base `TenantScopedManager` / `TenantScopedQuerySet` automatically filters by the requesting user's organization context — application code should never need to remember to add `.filter(organization=...)` manually; it's the default.
- API views additionally enforce organization scope in `permission_classes` (defense in depth — see `10-RBAC-Permissions.md`) so a bug in the manager doesn't silently leak cross-tenant data.
- **Trade-off accepted**: shared-schema is operationally simpler and cheaper to run than schema-per-tenant, at the cost of needing rigorous discipline on every new model/query to respect the tenant boundary. This is mitigated by the manager-level default filtering plus mandatory code-review checklist item (see `26-Testing-Strategy.md`).

## 7.4 Layered Backend Design (per Django app)

```
elections/
├── models.py          # Election, Position, ElectionStateTransition
├── serializers.py      # DRF serializers, one per API shape (not 1:1 with models)
├── views.py            # ViewSets — thin, delegate to services.py
├── services.py          # Business logic: state transitions, eligibility checks
├── permissions.py      # IsOrgAdmin, IsElectionOfficerForElection, etc.
├── tasks.py            # Celery tasks: scheduled state transitions, tally trigger
├── signals.py          # e.g., on Nomination approved → notify candidate
└── tests/
```

**Rule**: Views never contain business logic directly — they call `services.py` functions. This keeps the state-machine logic (election lifecycle, vote-casting atomicity) unit-testable without spinning up the HTTP layer, and keeps the same logic reusable from Celery tasks and the Django admin.

## 7.5 Election State Machine

```
Draft ──publish──▶ Published ──nomination window opens──▶ Nomination Open
                                                                │
                                                     nomination window closes
                                                                ▼
                                                        Nomination Closed
                                                                │
                                                       voting window opens
                                                                ▼
                                                          Voting Open
                                                                │
                                                       voting window closes
                                                                ▼
                                                     Results Provisional
                                                                │
                                                  grievance window elapses
                                                                ▼
                                                        Results Final
```

Implemented as an explicit `ElectionState` enum + `ElectionStateTransition` audit table (not just an updated field) — every transition is a new row, giving a free timeline/history without extra logging code.

## 7.6 Real-Time Layer

- Django Channels + Redis channel layer powers the **live turnout dashboard** (`% voted`, not individual votes) and the **live vote-count feed** for elections where the org enables it.
- WebSocket consumers are scoped per-election-room; a consumer can only join the room for elections within its authenticated org context.

## 7.7 Background Jobs (Celery)

| Task | Trigger | Purpose |
|---|---|---|
| `transition_election_states` | Periodic (every minute) | Moves elections through time-based state transitions |
| `tally_election_results` | On `Voting Open → Voting Closed` | Runs the configured tally algorithm |
| `finalize_results` | Periodic, checks grievance deadline | Moves `Provisional → Final`, generates PDF certificate |
| `send_notification` | Event-driven (signals) | Dispatches email/SMS/push via the notification gateway |
| `process_member_import` | On CSV upload | Validates and creates Member rows asynchronously for large imports |

## 7.8 Deployment Topology (see `25-Deployment-DevOps.md` for full detail)

- API + Channels: containerized Django app (Gunicorn + Uvicorn worker for ASGI/Channels), behind Nginx.
- Celery workers + beat scheduler: separate containers, same codebase image.
- PostgreSQL: managed instance (e.g., Render/Railway/AWS RDS) with daily automated backups.
- Redis: managed instance, used for cache, Celery broker, and Channels layer (can be split into separate Redis instances at scale).

Continue to `08-Database-Design.md`.
