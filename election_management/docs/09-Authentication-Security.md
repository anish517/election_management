# 09. Authentication & Security

## 9.1 Authentication Flow

- **Credentials**: email or phone + password (Org Admin, Election Officer, Auditor, Observer) OR phone/email + OTP-only (Voter, Candidate — lower-friction, higher-turnout design choice).
- **Tokens**: JWT access token (short-lived, 15 min) + refresh token (long-lived, 7–30 days, rotated on use, stored hashed) via `djangorestframework-simplejwt`.
- **OTP delivery**: SMS via Sparrow SMS (Nepal) with email fallback; OTP valid 5 minutes, single-use, rate-limited to 5 requests per 15 minutes per identifier.
- **2FA**: optional, required by default for Org Admin and Super Admin roles; TOTP-based (authenticator app), not SMS-based, to avoid SIM-swap risk for the highest-privilege accounts.

## 9.2 Session & Device Management

- Refresh tokens are tied to a `device_id` + `user_agent` fingerprint; Org Admin can view and revoke active sessions for their own account.
- Vote-casting sessions specifically: a **short-lived, single-purpose token** is issued at the start of the voting flow and invalidated immediately after a successful vote submission — even if the user's main session remains active, they cannot "resume" a voting session to attempt a second submission through session replay.

## 9.3 Authorization (RBAC)

- Enforced via DRF `permission_classes`, layered:
  1. `IsAuthenticated`
  2. `BelongsToOrganization` (tenant boundary)
  3. Role-specific, e.g. `IsOrgAdmin`, `IsElectionOfficerForElection` (checks `election_role_assignments`, not just global role)
- Full matrix in `10-RBAC-Permissions.md`.

## 9.4 Transport & Storage Encryption

| Layer | Mechanism |
|---|---|
| In transit | TLS 1.2+ everywhere; HSTS enabled |
| At rest (database) | Provider-level disk encryption (e.g., RDS/Render managed encryption) |
| At rest (files) | S3/Cloudinary server-side encryption for candidate documents, photos |
| Passwords | Argon2 (preferred) or bcrypt, never reversible encryption |
| Sensitive PII columns (national ID, if collected) | Application-level field encryption (AES-256-GCM) in addition to disk encryption |

## 9.5 Vote Anonymization Design

This is the core trust guarantee of the platform (BR-04 in `06-Software-Requirements-Specification.md`) and deserves its own explanation of *how*, not just *that*.

**Problem**: the system must (a) guarantee exactly one vote per eligible voter, while (b) guaranteeing no one — including database administrators — can determine how a specific voter voted.

**Approach** (application-layer separation, not exotic cryptography, chosen for auditability and maintainability at this stage — cryptographic e2e-verifiability is noted as a future enhancement in `28-Roadmap.md`):

1. When a voter casts a ballot, the request is authenticated (we know *who* is voting).
2. The API layer validates eligibility (`voter_rolls` lookup) and atomically flags `has_voted = true` on the `voter_rolls` row — **this is the only place voter identity is recorded in connection with the voting event.**
3. The actual ballot content is written to the `votes` table **with no foreign key to the voter, member, or user table** — only a `position_id` and the `choice_data`.
4. These two writes happen in the same database transaction (so a crash mid-write can't produce a "voted" flag with no corresponding ballot, or vice versa) but through **separate code paths with no shared identifier** — the ballot row contains nothing that traces back to step 2 except its `cast_at` timestamp, which is intentionally not unique enough to correlate (multiple ballots share timestamps at any real voting volume).
5. The voter's receipt hash is derived from the ballot content + a server-side secret + timestamp — it lets the *voter* independently verify their own ballot is present in the final tally (by recomputing the hash themselves against published anonymized results, in the v2 "public verifiability" mode — see `28-Roadmap.md`), without the hash itself revealing the choice to anyone who doesn't already know it.

**What this does NOT protect against**: a compromised application server that logs requests mid-flight (e.g., at the load balancer or an insufficiently scoped application log) could theoretically observe the plaintext request. Mitigations: request/response bodies containing ballot content are explicitly excluded from all logging (structured logging with an explicit denylist field, not just "don't log by convention"), and access to production logs is itself RBAC- and audit-controlled.

## 9.6 OWASP Top 10 — Applied Mitigations

| Risk | Mitigation |
|---|---|
| Broken access control | Layered permission classes (§9.3) + automated tests asserting cross-tenant and cross-role access is denied (see `26-Testing-Strategy.md`) |
| Cryptographic failures | TLS everywhere, Argon2/bcrypt password hashing, field-level encryption for sensitive PII |
| Injection | Django ORM parameterized queries by default; raw SQL banned outside reviewed exceptions |
| Insecure design | Threat-modeled explicitly for the voting flow (§9.5); state machine prevents invalid transitions at the model layer, not just UI |
| Security misconfiguration | Infra-as-code for deployment config (see `25-Deployment-DevOps.md`); no default credentials shipped |
| Vulnerable/outdated components | Automated dependency scanning (Dependabot/Renovate) in CI |
| Authentication failures | Rate-limited OTP, JWT short expiry, 2FA for admin roles |
| Software/data integrity failures | Signed release artifacts in CI/CD; audit log integrity via append-only DB grants |
| Logging/monitoring failures | Structured audit logging (§`19-Audit-Compliance.md`) with explicit denylist for sensitive fields |
| Server-side request forgery | Outbound requests (webhooks, payment callbacks) validated against an allowlist of expected hosts |

## 9.7 Rate Limiting

- DRF throttling classes: `AnonRateThrottle` for unauthenticated endpoints (OTP request, login), `UserRateThrottle` for authenticated write endpoints.
- Vote-casting endpoint specifically: throttled per-voter-per-election (not just per-IP), since IP-based throttling alone would incorrectly block many voters behind the same NAT (common in Nepal's mobile network topology).

## 9.8 Security Review Cadence

- Dependency scanning: continuous (CI).
- Internal security review: before each major release.
- External penetration test: before GA and annually thereafter (see `01-Introduction.md` §1.4, Objective 5).

Continue to `10-RBAC-Permissions.md`.
