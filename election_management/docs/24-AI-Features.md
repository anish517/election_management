# 24. AI Features (v1.1+ / Premium)

> All AI features described here operate on **aggregate, anonymized, or metadata-level signals only** — never on individual vote content. This is a hard constraint, not a design preference: anything that required correlating AI analysis with an individual's vote choice would violate the core anonymization guarantee in `09-Authentication-Security.md` §9.5 and is explicitly out of scope, permanently.

## 24.1 Anomaly & Fraud Detection

Signals monitored (all metadata/behavioral, not vote content):

| Signal | What It Flags |
|---|---|
| Voting velocity from a single IP/device fingerprint | Potential ballot-stuffing via automation or shared-device abuse |
| Unusual turnout spike patterns (e.g., 95% turnout in the last 5 minutes of a window) | Possible last-minute coordinated activity worth a human look |
| OTP request patterns (many requests, few completions, from clustered numbers) | Possible credential-stuffing or account-enumeration attempt |
| Nomination document similarity across unrelated candidates | Possible fraudulent/copied documentation, flagged for Election Officer manual review |
| Login geography inconsistent with member's registered region (soft signal, not a block) | Possible account compromise |

- Output: a **risk score + explanation**, surfaced to the Election Officer/Auditor as a flag for human review — the system never auto-blocks a vote or auto-disqualifies a candidate based on an AI signal. Human review is mandatory before any action.

## 24.2 AI-Assisted Reporting

- Auto-generated plain-language election summary ("Turnout was 68%, up from 61% in the previous election; the President race had the closest margin at 4%") appended to the standard Election Summary Report (§18.1) — generated from the same structured aggregate data already computed, not from raw ballot access.

## 24.3 AI Candidate Assistant (Candidate-Facing)

- Optional writing assistant to help candidates draft/polish their manifesto text — operates only on the candidate's own draft content they've explicitly opted into sharing, with a clear "AI-assisted" indicator; never auto-publishes without candidate review.

## 24.4 AI Risk Scoring for Organizations (Super Admin-Facing)

- Aggregate signals (payment failures, support ticket volume, unusual admin activity patterns) to flag organizations at risk of churn or in need of proactive support outreach — a business-operations tool, unrelated to election integrity signals in §24.1.

## 24.5 Explicitly Out of Scope

- Any AI feature that infers, predicts, or reconstructs individual voting behavior from patterns.
- Any AI-driven automatic candidate approval/rejection (approval remains a human decision per `14-Candidate-Management.md`, AI may only assist document review, never decide).
- Voter-facing "AI vote recommendation" features — inconsistent with the platform's neutrality obligations.

## 24.6 Roadmap Note

These are premium-tier, v1.1+ features layered on top of the deterministic core platform — the MVP (`05-Product-Requirements.md` §5.2) ships without them and remains fully functional; AI features are additive tooling for larger organizations with higher-stakes elections, not a dependency for basic operation.

Continue to `25-Deployment-DevOps.md`.
