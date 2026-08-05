# 11. Organization Management

## 11.1 Purpose

Defines how an organization ("tenant") is onboarded, configured, branded, and billed — the container every other module operates inside.

## 11.2 Organization Lifecycle

```
Signup ──▶ Trial (14 days, full features, capped at 50 voters) ──▶ Active (paid)
                                                    │
                                                    └──▶ Expired Trial (read-only, prompted to upgrade)

Active ──▶ Past Due (payment failed, 7-day grace) ──▶ Suspended (locked, data retained 90 days) ──▶ Purged
```

## 11.3 Organization Profile Fields

| Field | Editable By | Notes |
|---|---|---|
| Name, logo, brand color | Org Admin | Used across voter-facing screens and PDF certificates |
| Organization type | Org Admin (set once at signup, changeable via support request) | Drives default terminology (e.g. "Board Member" vs "Committee Member") shown in templates |
| Timezone | Org Admin | Default `Asia/Kathmandu` |
| Default language | Org Admin | `ne` / `en`, per-user override available |
| Grievance window length | Org Admin | Default 3 days, used to compute `result_contest_deadline` |
| Voter roll freeze offset | Org Admin | Default: nomination-open date |
| Retention period | Org Admin (cannot go below platform minimum of 1 year) | Default 7 years |

## 11.4 Branding & White-Label (v1.1+)

- v1: logo + single brand color applied to voter-facing UI and PDF certificates.
- v1.1+: custom subdomain (`org-name.emsplatform.com`), full custom domain (enterprise tier only).

## 11.5 Organization Admin Onboarding Flow

1. Signup with email/phone → OTP verification.
2. Create organization profile (name, type, timezone).
3. Select subscription plan (see `27-Monetization-Pricing.md`) or start trial.
4. Guided setup checklist: import members → configure first election → invite an Election Officer (optional).
5. First election created within trial triggers a "setup complete" milestone used for activation-rate tracking.

## 11.6 Multi-Organization Users

A person can belong to multiple organizations (e.g., a professional who's both a cooperative member and a college alum association member). Each membership is a distinct `Member` row scoped to its `Organization`, but they may share a single `User` login (matched by verified email/phone) — the org switcher in the Flutter app lets them move between org contexts without re-authenticating.

## 11.7 Organization Settings — Election Defaults

Org-level defaults that pre-fill (but don't lock) new election creation:

- Default nomination window length
- Default voting window length
- Default silent-period length
- Default result visibility (`admin_only` / `org_members` / `public`)
- Whether Election Officers may self-publish or require Org Admin co-sign

## 11.8 Deactivation & Data Export

- Org Admin can request full data export (members, elections, results, audit logs — **not** raw vote content, which remains permanently anonymized even on export) at any time.
- On cancellation, organization enters `Suspended`, data retained per retention policy, then purged — Org Admin is notified 30 and 7 days before purge.

Continue to `12-Member-Management.md`.
