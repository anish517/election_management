# 06. Software Requirements Specification (SRS)

*Loosely structured per IEEE 830 conventions, adapted for an agile delivery process.*

## 6.1 Purpose

This SRS defines the functional and technical requirements for the Election Management System (EMS) at a level sufficient to drive database design (`08-Database-Design.md`), API design (`21-REST-API-Documentation.md`), and module-level specs (`11`–`20`).

## 6.2 Scope

In scope: multi-tenant organization management, member management, election lifecycle, candidate nomination, secret-ballot voting across multiple voting methods, automatic tallying, reporting, audit logging, and notifications, delivered via Flutter apps and a Django REST API.

Out of scope: see `01-Introduction.md` §1.7.

## 6.3 Actors

| Actor | Description |
|---|---|
| Super Admin | Anthropic-style platform operator; not tied to any single organization |
| Organization Admin | Owns an organization's account |
| Election Officer | Delegated authority over one or more specific elections |
| Candidate | A member who has filed a nomination |
| Voter | A member eligible to vote in a given election |
| Observer | Read-only, non-sensitive view access |
| Auditor | Read-only, includes audit-log access |
| Scheduler (system actor) | Background job engine (Celery) that triggers time-based state transitions |
| Notification Gateway (system actor) | External system actor representing FCM/SMS/Email providers |
| Payment Gateway (system actor) | External system actor representing Khalti/eSewa/Stripe |

## 6.4 Use Case Summaries

### UC-01: Create Organization
- **Actor**: Prospective Org Admin
- **Preconditions**: None
- **Main flow**: Admin signs up → verifies email/phone → creates org profile → selects subscription plan → org enters `Trial` or `Active` state
- **Postconditions**: Organization exists with one Org Admin user

### UC-02: Import Members
- **Actor**: Org Admin
- **Preconditions**: Organization exists
- **Main flow**: Admin uploads CSV → system validates rows (required fields, duplicate detection) → system reports row-level errors → admin confirms → members created in `Invited` status
- **Alternate flow**: Row has missing/invalid data → excluded from import, listed in error report, rest proceed
- **Postconditions**: Valid rows become Member records;

### UC-03: Create Election
- **Actor**: Org Admin or Election Officer (if pre-delegated)
- **Preconditions**: Organization has ≥1 active member
- **Main flow**: Creator defines election name, positions, seats per position, voting method per position, nomination window, voting window → saves as `Draft` → publishes
- **Business rule**: Voting window must start after nomination-close + configured buffer (default 24h) to allow ballot generation
- **Postconditions**: Election in `Published` state, visible to eligible members per its own eligibility rule (not yet open for nomination until window opens)

### UC-04: Submit Nomination
- **Actor**: Candidate (a Member)
- **Preconditions**: Election in `Nomination Open` state; member meets position eligibility rules
- **Main flow**: Member submits nomination form (bio, manifesto, photo, documents) → system creates Nomination in `Pending` status → notifies Election Officer
- **Postconditions**: Nomination queued for review

### UC-05: Review Nomination
- **Actor**: Election Officer
- **Main flow**: Officer reviews documents/eligibility → marks `Verified` → marks `Approved` (or `Rejected` with required reason)
- **Business rule**: A rejected candidate may only resubmit if `resubmission_allowed = true` on the election AND the nomination window is still open
- **Postconditions**: Approved candidates appear on the ballot; rejected candidates are notified with reason

### UC-06: Cast Vote
- **Actor**: Voter
- **Preconditions**: Election in `Voting Open` state; voter on frozen voter roll for this election; voter has not already voted
- **Main flow**: Voter authenticates (OTP) → views ballot (approved candidates per position, per configured voting method) → selects choice(s) → confirms → system records vote and issues receipt
- **Business rule**: Vote recording and voter's "has voted" flag update must occur in a single atomic transaction to prevent race-condition double voting
- **Postconditions**: Ballot recorded, anonymized from voter identity at the storage layer, receipt issued

### UC-07: Tally Results
- **Actor**: Scheduler (system actor), triggered at `voting_end_at`
- **Main flow**: System locks further voting → runs the tally algorithm matching the election's configured voting method → produces `Provisional` results → notifies Org Admin/Election Officer
- **Postconditions**: Results visible to Org Admin/Officer immediately; visible to voters/public per org's publish setting

### UC-08: Publish Final Results
- **Actor**: Scheduler (system actor) or Org Admin (manual early publish, logged)
- **Preconditions**: Grievance window elapsed with no upheld contest, OR Org Admin manually confirms early publish
- **Main flow**: System transitions results `Provisional → Final`, generates signed PDF certificate, notifies all voters
- **Postconditions**: Election archived; results immutable except by Super Admin emergency override (fully audit-logged)

### UC-09: Audit Election
- **Actor**: Auditor
- **Main flow**: Auditor requests audit log export for an election → system returns full action log (excluding vote content) → auditor may independently verify tally by recomputing from anonymized ballot records
- **Postconditions**: No system state change (read-only)

## 6.5 Business Rules (Consolidated)

| ID | Rule |
|---|---|
| BR-01 | One member = one vote per position per election, enforced at DB constraint level |
| BR-02 | Voter roll is frozen at a configured date; later membership changes don't retroactively affect eligibility for an in-progress election |
| BR-03 | A vote, once cast, cannot be changed or withdrawn (prevents coercion re-voting attacks unless the org explicitly enables "revote overrides last vote" mode — off by default) |
| BR-04 | No user role, including Super Admin, has a query path that joins voter identity to vote content |
| BR-05 | Results are Provisional until the grievance window passes; Final results are immutable except via logged Super Admin emergency override |
| BR-06 | Candidate self-service editing (profile, manifesto) locks automatically at the configured silent-period start |
| BR-07 | Organization data is isolated at the query layer (every core model has a non-nullable `organization` FK, enforced via a base queryset manager) — never solely at the UI/permission layer |
| BR-08 | Payment is never required, requested, or accepted as a condition of casting a vote |

## 6.6 Assumptions

- Organizations have at least one designated Org Admin with a valid email and phone number.
- Voters have access to either SMS or email for OTP delivery (system supports both).
- Organizations are responsible for the underlying legal validity of the election per their own bylaws; the platform provides the tooling, not the certification.

## 6.7 Constraints

- Must run on infrastructure reachable from Nepal with acceptable latency (rules out some geo-restricted hosting regions).
- Must integrate with Khalti and eSewa, both of which have Nepal-specific merchant onboarding processes.
- Django REST Framework + PostgreSQL is the mandated backend stack (see `README.md` §2) for team-skill continuity with existing systems.

Continue to `07-System-Architecture.md`.
