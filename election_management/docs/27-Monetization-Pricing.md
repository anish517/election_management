# 27. Monetization & Pricing

## 27.1 Model

Per-organization SaaS subscription, tiered by active-voter count and feature access — not per-vote or purely per-election pricing, addressing the market's stated pain point with opaque/unpredictable per-election billing (see `04-Competitor-Analysis.md` §4.2).

## 27.2 Proposed Tiers (illustrative — validate against pilot org feedback before finalizing)

| Tier | Target | Voter Cap | Price (indicative) | Included |
|---|---|---|---|---|
| **Free** | Small clubs, student groups | ≤ 200 voters | NPR 0 | 1 active election at a time, FPTP/Multiple Choice only, email notifications only, standard branding |
| **Starter** | Housing societies, small associations | ≤ 1,000 voters | NPR 5,000–8,000 / year | Unlimited elections, SMS notifications, basic branding, PDF certificates |
| **Growth** | Cooperatives, mid-size associations | ≤ 10,000 voters | NPR 20,000–35,000 / year | All voting methods (RCV, weighted, proxy), live dashboards, audit export, priority support |
| **Enterprise** | Large cooperatives, professional bodies, multi-branch orgs | Custom | Custom quote | White-label/custom domain, webhooks/API access, AI features (§24), dedicated support, custom retention/compliance terms |

- **Pay-per-election** add-on option for organizations that run elections infrequently and don't want an annual commitment (addresses the housing-society segment identified in `02-Market-Research.md` §2.4).

## 27.3 Billing Mechanics

- Khalti/eSewa for Nepal-based organizations (local currency, local payment methods); Stripe for international/diaspora-linked organizations.
- Annual billing default with a modest discount vs. monthly, to reduce payment-processing overhead on low-margin lower tiers.
- Automatic plan-limit enforcement: organizations approaching their voter cap are notified proactively (not blocked mid-election) — a new election creation is blocked if it would exceed the plan's voter cap, with a clear upgrade prompt, but an election already in progress is never disrupted by a billing event.

## 27.4 Free Tier as Acquisition Funnel

- Positioned explicitly as a trust-building and word-of-mouth funnel (per `02-Market-Research.md` §2.4): a student union or small club running a free election becomes a reference/demo for the next paying cooperative or association board election.

## 27.5 Revenue Considerations

- Primary revenue: subscription tiers.
- Secondary (later-stage): nomination-fee payment processing convenience fee (optional, org-configurable, transparently disclosed — the platform never takes a cut of anything resembling a "cost to vote," per BR-08).
- Enterprise: custom implementation/onboarding services for large multi-branch organizations (e.g., a national professional association with district chapters each running their own election under one parent org).

## 27.6 Churn & Retention Considerations

- Because usage is inherently periodic (an org might only run one election a year), month-to-month engagement metrics are less meaningful than **election-cycle retention** (did they come back for the next election cycle) — this should be the primary retention KPI, not daily/monthly active users.

Continue to `28-Roadmap.md`.
