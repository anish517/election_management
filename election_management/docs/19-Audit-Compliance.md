# 19. Audit & Compliance

## 19.1 What Gets Logged

Every state-changing action across the platform, per BR-07/FR-7 in `05-Product-Requirements.md` and `06-Software-Requirements-Specification.md`:

| Category | Example Events |
|---|---|
| Organization | `org.created`, `org.plan_changed`, `org.suspended` |
| Membership | `member.imported`, `member.status_changed`, `member.suspended` |
| Election | `election.created`, `election.published`, `election.state_transitioned`, `election.cancelled` |
| Candidate | `nomination.submitted`, `nomination.verified`, `nomination.approved`, `nomination.rejected`, `nomination.withdrawn` |
| Voting | `vote.cast` (event + position only — **never** choice content), `voter_roll.frozen` |
| Results | `results.tallied`, `results.recounted`, `results.finalized`, `results.contested` |
| Access | `user.login`, `user.login_failed`, `session.revoked`, `role.assigned` |
| Data | `report.exported`, `data.export_requested` |
| Admin overrides | `emergency_override.executed` (Super Admin only — highest-scrutiny event type) |

## 19.2 What Never Gets Logged

- Individual vote content (candidate/choice selected).
- Any data that could re-establish a voter-to-vote link (per the anonymization design in `09-Authentication-Security.md` §9.5).
- Raw request/response bodies for voting endpoints (explicit denylist at the logging middleware level, not a convention that can be forgotten).

## 19.3 Immutability

- `audit_logs` table has **no `UPDATE` or `DELETE` grant** for any application-level database role — enforced at the PostgreSQL role/permission layer, so even a bug in application code cannot silently alter history.
- Retention purges (per `03-Nepal-Election-Workflow.md` §3.6) run as a separate, explicitly-audited process (`retention_purge.executed`, itself logged before the purge removes older entries) rather than ad-hoc deletion.

## 19.4 Auditor Capabilities

- Read-only access to: full audit log for their assigned scope (org-wide or election-specific), anonymized `votes.choice_data` for independent tally verification, and recount initiation (request only — Election Officer executes, per RBAC matrix in `10-RBAC-Permissions.md`).
- Auditor actions (viewing, exporting, requesting recount) are themselves logged — auditing the auditor.

## 19.5 Independent Verifiability

Because the tally algorithms are pure functions over anonymized data (`15-Voting-Engine.md` §15.10), an Auditor can:

1. Export the full anonymized `choice_data` set for a position.
2. Independently recompute the tally using their own script (not trusting the platform's computation).
3. Compare against the platform-published result — any mismatch is a serious, immediately escalated finding.

This is the practical (non-cryptographic) verifiability model for v1; see `28-Roadmap.md` for the planned upgrade path to cryptographic end-to-end verifiability (Helios-style) for organizations that require it.

## 19.6 Compliance Posture

- **Not** a certified national election system — explicitly positioned as a tool the organization's own election committee operates (per `03-Nepal-Election-Workflow.md` header disclaimer).
- Data retention, export, and deletion capabilities are designed to be compatible with typical cooperative/association audit and record-keeping expectations, but each organization remains responsible for confirming compliance with its own governing act/bylaws.
- Security review cadence: see `09-Authentication-Security.md` §9.8.

## 19.7 Legal Hold

- Org Admin (or Super Admin, in a dispute affecting the platform) can place an election under "legal hold," which blocks the automatic retention-purge job from ever removing that election's data until the hold is explicitly lifted — logged both ways.

Continue to `20-Notification-System.md`.
