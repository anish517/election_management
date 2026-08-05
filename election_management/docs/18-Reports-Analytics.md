# 18. Reports & Analytics

## 18.1 Report Types

| Report | Audience | Contents |
|---|---|---|
| **Election Summary** | Org Admin, Election Officer | Positions, candidates, turnout %, winners, timeline of state transitions |
| **Turnout Report** | Org Admin, Election Officer, Observer | Turnout by department/region/membership-tier (aggregate only, never individual) |
| **Candidate Report** | Org Admin, Election Officer | Per-candidate nomination status, vote share (post-finalization only) |
| **Voter Report** | Org Admin | Who has/hasn't voted (participation only — never linked to choice) — used for reminder targeting |
| **Audit Report** | Auditor, Org Admin | Full audit-log export for the election, per `19-Audit-Compliance.md` |
| **Organization Report** | Org Admin, Super Admin | Cross-election summary: elections run, avg. turnout trend, member growth |
| **Financial/Billing Report** | Org Admin | Subscription history, payments, invoices |

## 18.2 Live Dashboards

- **Election Officer live view**: real-time turnout %, votes-cast counter (if `live_vote_count` enabled per election), remaining-voters count, powered by the Django Channels layer (`07-System-Architecture.md` §7.6).
- **Org Admin cross-election dashboard**: active elections, upcoming elections, recent member growth, subscription status — BS-date-aware, mirroring the KPI-card pattern already used in cooperative admin dashboards, adapted to election-specific metrics (turnout trend, active nominations pending review) instead of attendance metrics.

## 18.3 Turnout Analytics Detail

- Turnout by department/region/membership tier, computed from `voter_rolls.has_voted` joined against `members` — never joined against `votes`.
- Turnout-over-time chart (hourly buckets) during an open voting window, useful for the Election Officer to decide whether to extend reminder-notification pushes.

## 18.4 Export Formats

- PDF (formatted reports, using the same certificate-generation pipeline as §17.7)
- Excel/CSV (raw tabular export for further analysis — turnout by segment, candidate lists)
- All exports are logged in `audit_logs` (who exported what, when) since exported data leaving the platform is itself a security-relevant event.

## 18.5 Cross-Election Trend Analytics (Org Admin)

- Turnout trend across the organization's election history (helps demonstrate governance improvement over time — a meaningful selling point for cooperative transparency, per `02-Market-Research.md` §2.6).
- Nomination-to-approval time trend (process efficiency metric).
- Member growth vs. active-voter growth (engagement health).

## 18.6 Super Admin Platform Analytics

- Cross-organization aggregate metrics only (no access to any individual org's member PII or election content beyond what's needed for support): active org count, elections run per month, platform-wide uptime, support ticket volume by category.

Continue to `19-Audit-Compliance.md`.
