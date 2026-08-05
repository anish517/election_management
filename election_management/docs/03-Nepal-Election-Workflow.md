# 03. Nepal Election Workflow & Compliance Considerations

> **Disclaimer**: This document describes common organizational election practices and technical accommodations for the Nepali context. It is **not legal advice**. Any organization using this platform for a legally significant election (e.g., a cooperative's statutory AGM election) should have its own election committee and legal counsel confirm compliance with the relevant act/bylaws (e.g., Cooperative Act, Company Act, or the organization's own constitution).

## 3.1 Common Nepali Organizational Election Patterns

Most Nepali membership organizations (cooperatives, associations, clubs) follow a broadly similar structure inspired by, but distinct from, national Election Commission processes:

1. **Election Committee formation** — the organization forms an internal election committee (often 3–5 members) responsible for conducting the election; this maps to the **Election Officer** role.
2. **Voter list finalization** — based on paid-up membership / share status as of a cutoff date ("voter roll freeze date").
3. **Nomination period** — candidates file nominations, often with a nomination fee and proposer/seconder requirement.
4. **Nomination withdrawal window** — a short period where candidates may withdraw before the final candidate list is locked.
5. **Silent/campaign-restriction period** — some organizations restrict campaigning in the final 24–48 hours before voting.
6. **Voting day(s)** — often a single day, sometimes extended for remote members.
7. **Counting & result declaration** — public or committee-witnessed counting, often followed by a formal declaration document.
8. **Grievance/appeal window** — a defined period (e.g., 3–7 days) during which results can be formally contested.

## 3.2 System Support for This Workflow

| Stage | EMS Feature |
|---|---|
| Election Committee formation | `Election Officer` role, scoped to a single election, assignable by Org Admin |
| Voter list freeze | `voter_roll_freeze_date` field on `Election`; membership status snapshot taken at freeze, not read live afterward |
| Nomination period | `nomination_open_at` / `nomination_close_at` window; optional nomination fee via Khalti/eSewa |
| Withdrawal window | `withdrawal_deadline`; candidate self-service withdrawal before this date |
| Silent period | `campaign_silent_from`; candidate profile edits and messaging features lock automatically |
| Voting day(s) | `voting_start_at` / `voting_end_at`, timezone-aware, BS-calendar-displayed |
| Counting | Automatic tally + optional manual witnessed recount mode (see `17-Vote-Counting-Results.md`) |
| Result declaration | Auto-generated, downloadable PDF result certificate, timestamped and hash-signed |
| Grievance window | `result_contest_deadline`; results remain "provisional" until this passes, then lock as "final" |

## 3.3 Bikram Sambat (BS) Calendar Support

All election-facing dates (nomination period, voting day, result declaration) must display in **BS by default**, with AD shown as secondary, consistent with how members actually think about dates. This reuses the BS-calendar utilities (`nepali_utils`-based) already validated in prior cooperative-management work — including the corrected `isToday`, grid-offset, and month-length logic.

- Admin-facing scheduling UI: BS date picker as primary input, converts to AD internally for all logic/storage.
- Voter-facing countdown ("voting closes in..."): BS-labeled, AD stored.
- All stored dates: **AD in the database** (source of truth), BS is a display/input layer only — this avoids the BS/AD mismatch bugs seen in earlier calendar work.

## 3.4 Language & Localization

- Nepali (Devanagari) and English UI, switchable per-user.
- Candidate manifestos and ballot questions must support **bilingual entry** (organizations often require both).
- SMS notifications in Nepali via Sparrow SMS or similar local gateway (higher deliverability than international SMS providers for Nepali numbers).

## 3.5 Payments

- **Nomination fees** (if the org requires them) and **organization subscription billing**: Khalti and eSewa as primary gateways; Stripe as a secondary option for any international/diaspora-linked organizations.
- Payments are **never** collected for the act of voting itself — this is a hard rule to avoid any appearance of vote-buying/pay-to-vote.

## 3.6 Data Residency & Retention

- Election records (voter rolls, ballots — anonymized, results, audit logs) retained for a minimum of **7 years** by default (configurable per org), matching common cooperative/audit retention expectations in Nepal.
- Personally identifying voter data may be purged/anonymized after the retention period while preserving anonymized turnout and result statistics.

## 3.7 Known Sector-Specific Sensitivities

- Nepal's cooperative sector has experienced governance controversies; organizations adopting this platform will often cite "transparency" as their primary reason. Product messaging and audit features should treat this as the **core value proposition**, not a checkbox feature.
- Avoid any positioning that implies the platform itself "certifies" or "validates" an election as legally binding — that authority always remains with the organization's own election committee/constitution.

Continue to `04-Competitor-Analysis.md`.
