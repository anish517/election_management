# 02. Market Research

## 2.1 Market Segments

| Segment | Est. Org Count (Nepal, approx. order of magnitude) | Election Frequency | Willingness to Pay |
|---|---|---|---|
| Savings & Credit Cooperatives (SACCOS) | Thousands nationally | Annual/biennial AGM elections | Medium–High (regulatory pressure for transparency) |
| Colleges/Universities | Hundreds | Annual student union elections | Low–Medium (budget-constrained, but high visibility) |
| Professional associations | Dozens of national bodies + district chapters | Every 2–4 years | High (reputational stakes, contested races) |
| Housing societies | Growing (urban Kathmandu Valley) | Annual/biennial | Low (price-sensitive, small budgets) |
| Trade unions | Moderate | Periodic | Medium |
| NGOs/INGOs | Large number registered | Annual board rotation | Medium |

## 2.2 Why Now

- **Cooperative sector scrutiny**: Nepal's cooperative sector has faced repeated governance and transparency controversies, increasing regulatory and member pressure for verifiable election processes.
- **Smartphone penetration**: high enough in urban and semi-urban Nepal to make a mobile-first voter app viable for most target segments.
- **Digital payments normalized**: Khalti/eSewa adoption makes SaaS subscription billing to organizations (not just consumers) increasingly frictionless.
- **Post-pandemic normalization of remote participation**: organizations are more accepting of remote/digital AGMs and elections than pre-2020.

## 2.3 Buyer vs. User

These are frequently different people with different needs — a key product design input:

| Persona | Role | Primary Need |
|---|---|---|
| **Organization Admin** (buyer) | Cooperative manager, college registrar, association secretary | Compliance, low admin burden, defensible audit trail |
| **Election Officer** | Delegated by admin to run the specific election | Fast candidate approval, clear dashboard, no ambiguity on rules |
| **Voter** (end user) | Member | Simple, fast, trustworthy — must believe their vote is secret and counted |
| **Candidate** | Contestant | Fair, transparent approval process; visibility into their own status |
| **Auditor/Observer** | Internal or external oversight | Read-only access to logs and results without seeing individual votes |

## 2.4 Pricing Sensitivity by Segment

- **Cooperatives & associations**: can typically absorb a per-election or annual subscription fee (NPR 5,000–50,000+ range depending on member count), especially if it replaces the cost of printing ballots, hiring poll staff, and manual counting.
- **Student unions/small clubs**: extremely price-sensitive; a **free tier** (capped at member count, e.g. ≤200 voters) is likely necessary to acquire this segment and use it as a trust-building funnel toward larger, paying organizations.
- **Housing societies**: price-sensitive but low-frequency; a **pay-per-election** model may convert better than annual subscription.

See `27-Monetization-Pricing.md` for the full pricing model derived from this.

## 2.5 Key Risks

| Risk | Mitigation |
|---|---|
| Trust deficit — "how do I know my vote wasn't changed?" | Public, verifiable audit log; voter-facing vote receipt (hash, not content); optional independent observer accounts |
| Low digital literacy among some voter bases | Extremely simple voter UI; SMS-based OTP (not just email); phone-first design |
| Disputed results causing reputational risk to platform | Clear recount/audit tooling built in from day one, not bolted on later |
| Regulatory ambiguity for "official" cooperative elections | Position as a *tool the organization's own election committee operates*, not as the certifying authority — mirrors how e-signature platforms position themselves relative to legal validity |

## 2.6 Competitive Positioning

Positioned as the **Nepal-first, multi-org-type** alternative to international tools (see `04-Competitor-Analysis.md`) that are either too generic (not localized), too expensive for small/medium orgs, or too narrowly focused on one org type (e.g., only corporate shareholder voting).

Continue to `03-Nepal-Election-Workflow.md`.
