# 08. Database Design

**Engine**: PostgreSQL 15+. See `database/` folder for per-table detail files.

## 8.1 Entity Relationship Overview

```
Organization ──┬──< Member ──┬──< Nomination >── Election ──< Position ──< Nomination
               │              │                       │
               │              └──< Vote (anonymized) ──┘
               │
               ├──< Election ──< ElectionStateTransition
               ├──< Subscription ──< Payment
               ├──< User (org-scoped roles)
               └──< AuditLog
```

## 8.2 Core Tables

### `organizations`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| name | varchar | |
| slug | varchar unique | for subdomain/URL use |
| logo_url | varchar | |
| org_type | varchar | cooperative, college, association, club, housing_society, union, ngo, corporate, religious, political_party, other |
| address | text | |
| timezone | varchar | default `Asia/Kathmandu` |
| default_language | varchar | `ne` or `en` |
| subscription_plan_id | FK → subscription_plans | |
| status | varchar | trial, active, suspended, cancelled |
| created_at / updated_at | timestamptz | |

### `users`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| organization_id | FK, **nullable only for Super Admin** | |
| email | varchar unique | |
| phone | varchar | |
| password_hash | varchar | |
| role | varchar | super_admin, org_admin, election_officer, voter, candidate, observer, auditor — see note below |
| is_active | boolean | |
| last_login_at | timestamptz | |
| created_at | timestamptz | |

> **Note on `role`**: a flat `role` field is sufficient for org-wide roles (Org Admin, Voter). Election-scoped roles (Election Officer, Observer, Auditor assigned to a *specific* election) are modeled separately in `election_role_assignments` below — a user can be a plain Voter org-wide but Election Officer for one specific election.

### `election_role_assignments`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| user_id | FK → users | |
| election_id | FK → elections | |
| role | varchar | election_officer, observer, auditor |
| assigned_by | FK → users | |
| created_at | timestamptz | |

### `members`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| organization_id | FK | |
| user_id | FK → users, nullable until activated | |
| member_code | varchar | org-defined member ID |
| full_name | varchar | |
| photo_url | varchar | |
| gender | varchar | |
| email | varchar | |
| phone | varchar | |
| department | varchar | nullable |
| position_title | varchar | nullable — their org role, not election position |
| membership_status | varchar | active, suspended, expired |
| membership_expiry_date | date | nullable |
| created_at / updated_at | timestamptz | |

### `elections`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| organization_id | FK | |
| title | varchar | |
| description | text | |
| state | varchar | draft, published, nomination_open, nomination_closed, voting_open, voting_closed, results_provisional, results_final |
| voter_roll_freeze_date | date | |
| nomination_open_at / nomination_close_at | timestamptz | |
| withdrawal_deadline | timestamptz | |
| campaign_silent_from | timestamptz | nullable |
| voting_start_at / voting_end_at | timestamptz | |
| result_contest_deadline | timestamptz | computed from voting_end_at + org's grievance window setting |
| is_secret_ballot | boolean | default true |
| results_visibility | varchar | admin_only, org_members, public |
| created_by | FK → users | |
| created_at / updated_at | timestamptz | |

### `positions`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| election_id | FK | |
| title | varchar | e.g. "President", "Board Member" |
| seats_available | integer | |
| voting_method | varchar | fptp, multi_choice, ranked_choice, approval, weighted, proxy, yes_no |
| max_votes_per_voter | integer | relevant for multi_choice |
| eligibility_rule | jsonb | flexible rule for who may stand/vote for this position (department, region, etc.) |

### `nominations`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| position_id | FK | |
| member_id | FK → members | |
| status | varchar | pending, verified, approved, rejected, withdrawn |
| bio | text | |
| manifesto | text | |
| photo_url | varchar | |
| symbol_url | varchar | nullable — ballot symbol |
| documents | jsonb | array of document URLs |
| rejection_reason | text | nullable, required if status=rejected |
| reviewed_by | FK → users | nullable |
| submitted_at / reviewed_at | timestamptz | |

### `voter_rolls`
Snapshot table — decouples "who was eligible" from live member state (BR-02 in the SRS).

| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| election_id | FK | |
| member_id | FK → members | |
| frozen_at | timestamptz | |
| has_voted | boolean | default false |

### `votes` (anonymized ballot storage)
This is the most sensitive table in the schema — see `09-Authentication-Security.md` §9.5 for the full anonymization design rationale.

| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| position_id | FK | |
| **no voter_id column** | — | intentional; voter identity is never joinable to this row |
| choice_data | jsonb | shape depends on voting method (candidate_id for FPTP, ranked array for RCV, etc.) |
| ballot_hash | varchar | hash used to generate the voter's receipt, verifiable by the voter without exposing content to anyone else |
| cast_at | timestamptz | |

Voter identity linkage for the "has this person voted" check lives **only** in `voter_rolls.has_voted`, updated atomically alongside vote insertion within the same DB transaction, but as a separate table with no FK from `votes`.

### `results`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| position_id | FK | |
| status | varchar | provisional, final |
| tally_data | jsonb | full computed tally, method-specific |
| winners | jsonb | array of member_ids |
| certificate_pdf_url | varchar | nullable until generated |
| certificate_hash | varchar | |
| computed_at | timestamptz | |
| finalized_at | timestamptz | nullable |

### `audit_logs`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| organization_id | FK | |
| actor_user_id | FK → users, nullable (system actions) | |
| action | varchar | e.g. `election.published`, `nomination.approved`, `vote.cast` (event only, never content) |
| target_type / target_id | varchar / UUID | polymorphic reference |
| metadata | jsonb | non-sensitive context only |
| created_at | timestamptz | |

**Append-only**: no `UPDATE`/`DELETE` grants on this table for any application role; enforced at the PostgreSQL role/permission level, not just the ORM.

### `subscription_plans`, `subscriptions`, `payments`
Standard SaaS billing tables — full detail in `database/MongoDB-Collections.md` equivalent (`database/Billing-Tables.md`, generated in a later batch) and `27-Monetization-Pricing.md`.

### `notifications`
| Column | Type | Notes |
|---|---|---|
| id | UUID PK | |
| user_id | FK | |
| channel | varchar | email, sms, push |
| template_key | varchar | |
| status | varchar | queued, sent, failed |
| sent_at | timestamptz | |

## 8.3 Key Indexes

| Table | Index | Reason |
|---|---|---|
| `members` | `(organization_id, membership_status)` | fast eligibility filtering |
| `voter_rolls` | unique `(election_id, member_id)` | prevents duplicate roll entries |
| `voter_rolls` | `(election_id, has_voted)` | fast turnout calculation |
| `votes` | `(position_id)` | tally computation |
| `nominations` | `(position_id, status)` | ballot generation (approved only) |
| `audit_logs` | `(organization_id, created_at)` | timeline queries, retention purges |
| `users` | unique `(organization_id, email)` | one account per email per org (Super Admin excepted) |

## 8.4 Critical Constraints

```sql
-- One vote per voter per election, enforced via voter_rolls, not votes:
ALTER TABLE voter_rolls ADD CONSTRAINT uq_voter_roll UNIQUE (election_id, member_id);

-- has_voted transition must be atomic with vote insert — enforced at
-- the application transaction level (services.py: cast_vote()), wrapped in
-- select_for_update() on the voter_roll row to prevent race-condition double submits.
```

## 8.5 Soft Delete Strategy

- **Members, Organizations**: soft-deleted (`deleted_at` timestamp) to preserve historical election integrity (a past election's results must still resolve candidate/voter references even if a member later leaves the org).
- **Votes, Results, Audit Logs**: never deleted, only purged per the retention policy (`03-Nepal-Election-Workflow.md` §3.6) via a dedicated, logged retention job — not ad-hoc deletion.

Continue to `09-Authentication-Security.md`.
