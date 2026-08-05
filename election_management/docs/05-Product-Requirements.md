# 05. Product Requirements Document (PRD)

## 5.1 User Roles

| Role | Scope | Summary |
|---|---|---|
| Super Admin | Platform-wide | Manages organizations, subscriptions, platform health |
| Organization Admin | Single org | Full control over that org's members, elections, settings, billing |
| Election Officer | Single election (scoped) | Runs one election: approves candidates, monitors turnout, can trigger recount |
| Candidate | Self | Submits nomination, manages own profile/manifesto, views own status |
| Voter | Self | Views eligible elections, casts ballot, views own vote receipt |
| Observer | Single org or election (read-only) | Views live dashboards, reports — cannot see individual votes |
| Auditor | Single org or election (read-only) | Views audit logs, can trigger/verify recounts, cannot alter data |

Full permission matrix: `10-RBAC-Permissions.md`.

## 5.2 MVP Feature Set (v1.0)

Must ship for first paying organization:

- [ ] Organization signup, branding (logo, name, color), single subscription plan
- [ ] Org Admin invites members via CSV import or manual entry
- [ ] Member eligibility rules (active status, membership-paid flag)
- [ ] Election creation: name, positions, seats per position, nomination window, voting window
- [ ] Candidate self-nomination with photo, manifesto, document upload
- [ ] Candidate approval workflow (pending → verified → approved/rejected)
- [ ] Voting methods: **FPTP (single choice)** and **multiple-choice** at MVP; ranked-choice/weighted/proxy deferred to v1.1 (see `15-Voting-Engine.md`)
- [ ] Secret ballot with OTP-based voter authentication
- [ ] Live turnout dashboard (% voted, not who voted for whom)
- [ ] Automatic result tally + downloadable PDF result certificate
- [ ] Full audit log (who did what, when — never what was voted)
- [ ] Email + SMS notifications (nomination open, voting open, voting closing soon, results published)
- [ ] BS calendar display throughout
- [ ] Khalti/eSewa billing for org subscription

## 5.3 Deferred to v1.1+

- Ranked-choice (STV), weighted voting, proxy voting (see `15-Voting-Engine.md` for full spec — designed now, shipped later)
- WhatsApp notifications
- Public results portal (external, unauthenticated view)
- AI-based anomaly/fraud detection (`24-AI-Features.md`)
- Biometric/selfie identity verification
- White-label custom domain per organization

## 5.4 Functional Requirements

### FR-1 Organization Management
- FR-1.1 System shall support unlimited organizations, each with fully isolated member/election/candidate data.
- FR-1.2 Org Admin shall configure org profile (name, logo, address, timezone, default language).
- FR-1.3 System shall enforce subscription plan limits (e.g., max active voters) and block election creation past the limit until upgrade.

### FR-2 Member Management
- FR-2.1 Org Admin shall import members via CSV/Excel with validation (duplicate email/phone detection).
- FR-2.2 System shall track membership status (`active`, `suspended`, `expired`) and voting eligibility is derived from this, not manually toggled per election.
- FR-2.3 System shall snapshot the eligible voter list at the configured freeze date per election (see `03-Nepal-Election-Workflow.md` §3.2) — later membership changes do not retroactively affect an in-progress election's voter roll.

### FR-3 Election Lifecycle
- FR-3.1 Election shall move through states: `Draft → Published → Nomination Open → Nomination Closed → Voting Open → Voting Closed → Results Provisional → Results Final`.
- FR-3.2 State transitions shall be time-triggered (via scheduled job) or manually triggered by Election Officer where the org's rules allow manual override.
- FR-3.3 No state transition shall be reversible once votes have been cast, except by Super Admin under a logged emergency-override procedure.

### FR-4 Candidate Nomination
- FR-4.1 Candidate shall submit nomination only within the nomination window for an election they are eligible for (per position eligibility rules).
- FR-4.2 Election Officer shall verify/approve/reject nominations with a required reason field on rejection.
- FR-4.3 Rejected candidates shall be notified with the reason and, if the org's rules allow, may resubmit before the window closes.

### FR-5 Voting
- FR-5.1 Each eligible voter shall be able to cast exactly one ballot per position, per election.
- FR-5.2 System shall prevent duplicate voting through a unique `(voter, election)` ballot-cast constraint enforced at the database level, not just the application layer.
- FR-5.3 Ballot content shall be stored in a way that cannot be linked back to the voter's identity by any application-level query (see `09-Authentication-Security.md` §9.5 for the anonymization approach).
- FR-5.4 Voter shall receive a vote confirmation receipt (a hash/reference code) proving a vote was recorded, without revealing its content.

### FR-6 Results
- FR-6.1 System shall auto-calculate results per the election's configured voting method immediately upon voting close.
- FR-6.2 Results shall be `Provisional` until the grievance window (§3.2 of `03-Nepal-Election-Workflow.md`) passes, then auto-transition to `Final`.
- FR-6.3 System shall generate a downloadable, tamper-evident (hash-stamped) PDF result certificate.

### FR-7 Audit
- FR-7.1 Every state-changing action shall be recorded in an append-only audit log with actor, timestamp, and action type.
- FR-7.2 Audit logs shall never contain the content of an individual vote.

## 5.5 Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Availability** | 99.5% uptime during any active voting window (higher SLA tier available) |
| **Performance** | Ballot submission p95 < 800ms under expected concurrent load for the org's voter count |
| **Scalability** | A single election shall support at least 100,000 concurrent eligible voters without redesign |
| **Security** | See `09-Authentication-Security.md` — JWT, encryption at rest/in transit, OWASP Top 10 mitigations |
| **Auditability** | Every vote is individually verifiable by the voter (via receipt) without revealing choice to anyone else |
| **Localization** | Full BS calendar + Nepali/English bilingual support at MVP |
| **Accessibility** | WCAG 2.1 AA target for voter-facing screens |
| **Data retention** | Configurable per-org, default 7 years (see `03-Nepal-Election-Workflow.md` §3.6) |
| **Offline tolerance** | Voter app shall gracefully handle intermittent connectivity (retry submission, never silently drop a vote) |

## 5.6 Sample User Stories

```
As an Organization Admin,
I want to import my 3,000 members from an Excel file,
So that I don't have to manually create each member account.

As a Voter,
I want to receive an SMS reminder 24 hours before voting closes,
So that I don't miss my chance to vote.

As an Election Officer,
I want to reject a nomination with a required reason,
So that the candidate understands what to correct and the decision is defensible if challenged.

As an Auditor,
I want to view the full audit trail of an election,
So that I can verify no unauthorized state changes occurred, without being able to see who voted for whom.

As a Candidate,
I want to see my nomination status change from Pending to Approved,
So that I know I'm confirmed to appear on the ballot.
```

## 5.7 Acceptance Criteria (sample — Voting)

**Feature: Cast Ballot**
- Given a voter is authenticated and on the eligible voter roll for an open election
- When they submit a valid ballot for every required position
- Then the system records the ballot, issues a receipt code, and marks that voter as "voted" for that election
- And the voter cannot submit a second ballot for the same election
- And no user interface, log, or report anywhere in the system displays which candidate that voter selected

Continue to `06-Software-Requirements-Specification.md`.
