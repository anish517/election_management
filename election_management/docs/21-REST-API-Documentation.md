# 21. REST API Documentation

**Base URL**: `https://api.emsplatform.com/v1/`
**Auth**: `Authorization: Bearer <jwt_access_token>` unless noted. All tenant-scoped endpoints implicitly filter by the authenticated user's `organization_id`.

## 21.1 Authentication

```
POST /auth/register/                  { email, phone, password, org_name }  → creates Org Admin + Organization (trial)
POST /auth/login/                     { email_or_phone, password }         → { access, refresh }
POST /auth/token/refresh/             { refresh }                          → { access }
POST /auth/otp/request/               { phone_or_email }                   → { otp_sent: true }
POST /auth/otp/verify/                { phone_or_email, otp }              → { access, refresh }
POST /auth/2fa/setup/                 (auth required)                       → { qr_code_url, secret }
POST /auth/logout/                    (auth required)                       → 204
```

## 21.2 Organizations

```
GET    /organizations/me/                             → current org profile
PATCH  /organizations/me/                              → update profile/branding
GET    /organizations/me/settings/                     → election defaults, retention config
PATCH  /organizations/me/settings/
```

## 21.3 Members

```
GET    /members/?status=active&department=Finance      → list (paginated, filterable)
POST   /members/                                       → create single member
POST   /members/import/                                 multipart CSV → { job_id }
GET    /members/import/{job_id}/status/                 → { created, updated, skipped: [...] }
GET    /members/{id}/
PATCH  /members/{id}/
DELETE /members/{id}/                                    → soft delete
```

## 21.4 Elections

```
GET    /elections/?state=voting_open
POST   /elections/                                       → create (Draft)
GET    /elections/{id}/
PATCH  /elections/{id}/
POST   /elections/{id}/publish/
POST   /elections/{id}/cancel/                            { reason }
POST   /elections/{id}/clone/
GET    /elections/{id}/turnout/                            → { eligible, voted, turnout_pct } (live, WebSocket also available)
GET    /elections/{id}/audit-log/                          (Auditor/Org Admin only)
```

## 21.5 Positions & Ballot Builder

```
GET    /elections/{election_id}/positions/
POST   /elections/{election_id}/positions/
PATCH  /positions/{id}/
GET    /positions/{id}/ballot-preview/?lang=ne             (Election Officer only)
```

## 21.6 Candidates & Nominations

```
POST   /positions/{position_id}/nominations/                { bio, manifesto, photo, documents }
GET    /nominations/?status=pending&election_id=...
PATCH  /nominations/{id}/verify/
PATCH  /nominations/{id}/approve/
PATCH  /nominations/{id}/reject/                             { reason }
POST   /nominations/{id}/withdraw/
POST   /nominations/{id}/appeal/                             { statement }
```

## 21.7 Voting

```
GET    /elections/{id}/ballot/                                (voter-scoped: only their eligible positions, approved candidates)
POST   /elections/{id}/vote-session/                           → { voting_session_token }  (short-lived, single-purpose — §9.2)
POST   /vote-sessions/{token}/cast/                             { votes: [{position_id, choice_data}, ...] }
                                                                 → { receipt_hash, cast_at }
                                                                 (session token invalidated immediately after)
GET    /elections/{id}/my-receipt/                              → voter's own receipt (never choice content)
```

## 21.8 Results

```
GET    /elections/{id}/results/                                (visibility per election setting)
POST   /elections/{id}/recount/                                 { reason }  (Auditor/Election Officer)
GET    /elections/{id}/results/certificate.pdf
POST   /elections/{id}/results/contest/                         { statement }  (grievance window only)
```

## 21.9 Reports

```
GET    /elections/{id}/reports/summary/
GET    /elections/{id}/reports/turnout/?group_by=department
GET    /organizations/me/reports/trend/
POST   /reports/{report_id}/export/                             { format: "pdf" | "csv" | "xlsx" }
```

## 21.10 Roles & Delegation

```
GET    /elections/{id}/roles/
POST   /elections/{id}/roles/                                    { user_id, role: "election_officer" | "observer" | "auditor" }
DELETE /elections/{id}/roles/{assignment_id}/
```

## 21.11 Billing

```
GET    /organizations/me/subscription/
POST   /organizations/me/subscription/upgrade/                    { plan_id }
POST   /payments/khalti/initiate/
POST   /payments/khalti/callback/                                 (webhook, signature-verified)
POST   /payments/esewa/initiate/
POST   /payments/esewa/callback/                                  (webhook, signature-verified)
```

## 21.12 Error Format

```json
{
  "error": {
    "code": "NOMINATION_WINDOW_CLOSED",
    "message": "Nominations can no longer be submitted for this election.",
    "field_errors": {}
  }
}
```

Standard HTTP status codes throughout: `400` validation, `401` unauthenticated, `403` unauthorized (including cross-tenant access attempts — never leaks whether the resource exists), `404` not found (within tenant scope), `409` conflict (e.g., duplicate vote attempt), `429` rate-limited.

## 21.13 Pagination & Filtering

- Cursor-based pagination on all list endpoints: `?cursor=...&page_size=50` (default 25, max 100).
- Standard filter query params documented per-endpoint above; all filtering happens server-side, tenant-scoped before any other filter is applied.

## 21.14 Webhooks (Outbound, v1.1+)

For organizations that want to integrate election events into their own systems (e.g., an existing member portal):

```
election.published, nomination.approved, voting.opened, voting.closed, results.finalized
```
Delivered as signed POST requests (HMAC-SHA256 signature header) to a configured org webhook URL, with retry-with-backoff on failure.

Continue to `22-Mobile-App-Flutter.md`.
