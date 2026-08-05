# 13. Election Management

## 13.1 Purpose

Covers election creation, configuration, scheduling, and lifecycle management — the central workflow of the platform.

## 13.2 Election Creation Wizard (Admin UX)

1. **Basics**: title, description, organization-type-aware terminology (e.g. "Committee Election" vs "Board Election").
2. **Positions**: add one or more positions, each with seats available, voting method (see `15-Voting-Engine.md`), and eligibility rule.
3. **Schedule** (BS-calendar-first input, per `03-Nepal-Election-Workflow.md` §3.3):
   - Nomination open/close
   - Withdrawal deadline
   - Silent period start (optional)
   - Voting start/end
   - Grievance window (pre-filled from org default, editable)
4. **Voter roll**: freeze date (defaults to nomination-open date), eligibility rule inherited from org default or overridden per election.
5. **Visibility**: results visibility (`admin_only` / `org_members` / `public`), live turnout dashboard on/off.
6. **Review & Publish**: validation pass (see §13.4) → `Draft` → `Published`.

## 13.3 Election Templates

Org Admins can save a completed election configuration as a reusable template (e.g., "Annual Board Election") to speed up recurring elections — copies positions, voting methods, and default schedule offsets (not the actual dates, which are re-picked each cycle).

## 13.4 Validation Rules at Publish Time

- Voting window must start ≥ nomination-close + org's configured buffer (default 24h).
- Every position must have ≥1 seat and a valid voting method.
- Grievance window must be ≥ platform minimum (24h) to allow contest submission.
- Election cannot publish with zero eligible voters on the projected roll (warning + confirmation, not a hard block, since roll composition can change before freeze date).

## 13.5 State Machine

Full diagram in `07-System-Architecture.md` §7.5. Election Management module owns:

- The Celery Beat-triggered `transition_election_states` task.
- Manual override actions (Org Admin/Election Officer, where org settings permit), each logged as an `ElectionStateTransition` row with `triggered_by` = user or `system`.

## 13.6 Multi-Position Elections

A single election can bundle multiple positions (e.g., President + Vice President + 3x Executive Member seats) voted on on the same ballot in the same voting window — each position tallies independently per its own configured voting method.

## 13.7 Election Cloning & Recurrence

- "Duplicate this election" action copies structure (positions, methods, eligibility rules) into a new `Draft` election, letting Election Officers avoid re-configuring recurring annual elections from scratch.
- No automatic recurrence/scheduling — every election is explicitly created and published, preventing accidental "silent" elections from running unattended.

## 13.8 Cancellation

- An election in `Draft` or `Published` (pre-nomination) can be cancelled outright.
- An election with an open nomination or voting window can only be cancelled by Org Admin with a required justification, logged, and all affected candidates/voters notified — this is a rare, high-visibility action by design, not a casual toggle.

Continue to `14-Candidate-Management.md`.
