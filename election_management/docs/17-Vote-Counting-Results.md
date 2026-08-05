# 17. Vote Counting & Results

## 17.1 Trigger

Automatic tally fires the instant an election transitions `Voting Open → Voting Closed` (time-triggered via `transition_election_states`, see `07-System-Architecture.md` §7.7). No manual "start counting" step exists in the default flow — removing this manual step removes a common source of delay and dispute in traditional elections.

## 17.2 Counting Modes

| Mode | Description | When Used |
|---|---|---|
| **Automatic** | System runs the tally algorithm (`15-Voting-Engine.md` §15.10) immediately, no human step | Default for all elections |
| **Witnessed Manual Recount** | Auditor/Election Officer triggers a re-run of the same deterministic algorithm against the same anonymized ballot set, optionally with a second Auditor present (logged) | On dispute, or org policy requiring routine recount for close margins |
| **Independent Verification** | Auditor exports anonymized `choice_data` and recomputes the tally with an independent script (not the platform's own tally service) | High-stakes elections, external audit requirement |

## 17.3 Invalid / Spoiled Ballots

- A ballot is only ever created in the `votes` table if it **passed server-side validation** at cast time (§16.4) — there is no concept of an "invalid ballot" reaching storage, because invalid submissions are rejected before acceptance, with the voter prompted to correct and resubmit before their `has_voted` flag is set.
- This differs deliberately from paper elections (where spoiled ballots are common) — digital validation at the point of casting eliminates the entire spoiled-ballot category rather than needing to count and report it after the fact.

## 17.4 Recount Procedure

1. Auditor or Election Officer initiates recount request (reason required).
2. If org policy requires dual sign-off, a second Auditor/Officer must confirm before it executes.
3. System re-runs the pure-function tally algorithm (§15.10) against the **same, unmodified** anonymized ballot set.
4. Result: either confirms the original tally (expected outcome — the algorithm is deterministic, so a recount without a code/data change should always match) or, if a bug/data issue is found, produces a corrected result with a full explanation logged and a Super-Admin-approved override for the discrepancy.
5. Recount request, participants, and outcome are all audit-logged.

## 17.5 Tie Handling

Per `15-Voting-Engine.md` §15.9 — recount first, then runoff or lot per org configuration.

## 17.6 Results Publication

| State | Visible To |
|---|---|
| `Results Provisional` | Org Admin, Election Officer, Auditor only |
| `Results Final` | Per election's `results_visibility` setting: Admin only / Org members / Public |

- Provisional → Final transition is automatic at the grievance-window deadline (`result_contest_deadline`), or early by Org Admin manual confirmation (logged as an explicit early-publish action).

## 17.7 Result Certificate

- Auto-generated PDF on finalization: election name, position(s), full vote breakdown (or aggregate-only, per org's transparency setting), declared winner(s), timestamp, and a `certificate_hash` (SHA-256 of the certificate content) printed on the document itself — allows anyone holding the PDF to verify it hasn't been altered by recomputing the hash.
- Uses the `docx`/`pdf` generation pipeline consistent with other cooperative-management document outputs already in use (payslips, reports).

## 17.8 Grievance / Contest Handling

- Any eligible voter or candidate may file a contest within the grievance window, routed to Org Admin with the specific concern (e.g., "candidate X was ineligible," "turnout number looks wrong").
- Filing a contest does **not** automatically block finalization — Org Admin reviews and decides whether to extend the provisional period, trigger an independent verification, or dismiss the contest with a logged reason. This keeps the platform from being trivially delayed by unfounded contests while still guaranteeing every contest is formally recorded and answered.

Continue to `18-Reports-Analytics.md`.
