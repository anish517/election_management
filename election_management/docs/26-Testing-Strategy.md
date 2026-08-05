# 26. Testing Strategy

## 26.1 Testing Pyramid

| Layer | Tooling | Focus |
|---|---|---|
| Unit | pytest (backend), `flutter_test` (frontend) | Tally algorithms (§15.10, pure functions — highest priority for exhaustive unit coverage), state-machine transitions, permission classes |
| Integration | pytest + Django test client (DRF `APITestCase`) | Full request/response cycles, tenant isolation, RBAC enforcement |
| End-to-End | Playwright/Appium (or Flutter integration_test) | Full election lifecycle: create org → import members → run election → cast votes → verify results |
| Security | OWASP ZAP, manual + external pentest | Per `09-Authentication-Security.md` §9.8 |
| Load | Locust/k6 | Peak-load voting-window scenario (§25.8) |

## 26.2 Priority Test Areas

### Vote Integrity (highest priority — this is the trust-critical path)
- One voter cannot cast two ballots for the same election (race-condition test: concurrent requests from the same voter, assert only one succeeds).
- Vote content is never retrievable joined to voter identity through any API endpoint, admin panel, or raw query, including as Super Admin.
- Tally algorithm correctness: exhaustive test vectors for FPTP, Multiple Choice, RCV/STV (including edge cases: exhausted ballots, exact quota, ties), Weighted, Yes/No with super-majority thresholds.
- Idempotent vote submission: retried submit with the same `voting_session_token` never creates a duplicate ballot.

### Tenant Isolation
- Automated test suite asserting that **every** list/detail endpoint, when queried by User A of Org 1, never returns data belonging to Org 2 — run as a generic cross-cutting test sweep across all viewsets, not just hand-picked endpoints, to catch a forgotten `TenantScopedManager` application on a new model.

### RBAC
- Matrix-driven test suite: for each role × each action in `10-RBAC-Permissions.md` §10.2, assert allowed actions succeed and disallowed actions return `403`, not `404` (to distinguish "no permission" from "resource leaked existence" bugs, per §21.12).

### State Machine
- Every valid transition succeeds; every invalid transition (e.g., attempting to open voting before nomination closes) is rejected at the model/service layer, not just the API layer.

## 26.3 Test Data & Fixtures

- Synthetic org fixtures covering each org type (cooperative, college, association, etc.) with realistic member counts, used across integration and load tests.
- Deterministic seeded random ballot ordering (§14.7) in tests — randomization is tested for correctness of *distribution*, not asserted on a specific fixed order.

## 26.4 Load Testing Scenarios

| Scenario | Target |
|---|---|
| Concurrent vote casting | 5,000 concurrent voters submitting within a 10-minute window, p95 submission latency < 800ms (NFR from `05-Product-Requirements.md` §5.5) |
| Bulk member import | 50,000-row CSV import completes within acceptable async job time, without blocking other org operations |
| Live dashboard under load | WebSocket turnout updates remain accurate and timely with 5,000+ connected dashboard viewers |

## 26.5 User Acceptance Testing (UAT)

- Pilot organizations (one from each of 2–3 target segments — e.g., one cooperative, one college) run a real (or shadow/parallel) election on the platform before GA, with structured feedback captured against the PRD's acceptance criteria (`05-Product-Requirements.md` §5.7).

## 26.6 CI Gate

- No PR merges to `main` without: passing unit + integration suite, no new high/critical dependency vulnerabilities, and coverage not regressing below the team's agreed floor (recommend starting at 80% for `voting`, `elections`, and `auth` apps specifically, given their trust-criticality — lower floors acceptable for less critical apps like `notifications`).

Continue to `27-Monetization-Pricing.md`.
