# 04. Competitor Analysis

## 4.1 Landscape Summary

The online election/voting software market is dominated by a handful of established international players, none of which are Nepal- or South-Asia-localized, and none of which offer true multi-tenant, multi-org-type architecture with local payment rails out of the box.

| Competitor | Positioning | Strengths | Weaknesses (relative to this EMS) |
|---|---|---|---|
| **ElectionBuddy** | Most widely known; targets unions, associations, universities; operating since 2012 | Broad feature set, strong mobile UX, ranked-choice and weighted voting, easy setup with templates | Pricing is largely quote-based and per-election/per-voter, which adds up for orgs running frequent elections; no public API for programmatic/embedded use; identity verification is mostly email-only with no government-ID option; hosting is outside the EU with limited public detail on storage-level encryption |
| **OpaVote** | Positions itself as the ranked-choice specialist | Free tier for small elections, straightforward setup, strong at STV/ranked-choice math | Narrower feature set outside ranked-choice; limited identity verification depth |
| **Helios Voting** | Open-source, cryptographically end-to-end-verifiable elections, popular in academic/technical circles | Strong cryptographic verifiability, free/open-source | Requires self-hosting and real technical expertise to operate; not designed for a non-technical org admin; no polished multi-tenant SaaS experience |
| **Simply Voting** | Enterprise-oriented, hosted, in operation since 2003 | Long track record, phone support, full-service hosted elections | Custom quotes/contracts rather than transparent pricing; less self-serve |
| **Assembly Voting** | Enterprise/high-trust elections, encryption-forward | Deep security credentials (claims 7,000+ elections run, 43M+ voters served), accessibility focus | Enterprise sales motion, not built for small orgs self-serving in minutes |
| **Google Forms / SurveyMonkey (informal use)** | Not an election tool but frequently misused as one by small orgs today | Free, familiar | No ballot secrecy, no voter verification, no one-person-one-vote enforcement, trivially contestable results |

## 4.2 Where This EMS Differentiates

1. **True multi-tenant, multi-org-type platform** — competitors above are mostly single-election, single-org-configured; none natively model "Organization → many org types → many elections" with per-org branding and role hierarchy out of the box.
2. **Nepal-first localization** — Bikram Sambat calendar, Nepali-language ballots, Khalti/eSewa billing, Sparrow SMS delivery. None of the competitors above localize for this market.
3. **Transparent, predictable pricing** — the reviewed market shows a common pain point: opaque, quote-based, or per-voter pricing that's hard to budget against. A flat per-organization subscription tier (see `27-Monetization-Pricing.md`) directly addresses this.
4. **API-first** — several competitors (notably ElectionBuddy) are called out in third-party comparisons as lacking a public API for programmatic election creation. A REST API (see `21-REST-API-Documentation.md`) is a first-class part of this platform from day one, enabling embedding into an organization's existing member portal.
5. **Built-in audit trail without enterprise pricing** — strong audit/compliance tooling (see `19-Audit-Compliance.md`) is a baseline feature, not reserved for an enterprise tier, addressing the trust gap that drives organizations to (or away from) a platform in the first place.

## 4.3 Positioning Statement

> For membership-based organizations in Nepal running periodic committee, board, or union elections, this EMS is the multi-tenant election platform that combines the flexibility of international tools like ElectionBuddy and OpaVote with local currency billing, Bikram Sambat scheduling, and Nepali-language ballots — at transparent, predictable pricing.

## 4.4 Sources

- GoodFirms — Best Voting Software 2026 (goodfirms.co/voting-software)
- SourceForge — ElectionBuddy Alternatives & Competitors
- Nemovote — Online Voting Software Review 2026
- vote.direct — Best Online Voting Tools 2026: Pricing & Features Compared
- vote.direct — Compare: ElectionBuddy vs OpaVote vs Simply Voting vs vote.direct
- vote.direct — HOA Election Software Cost Comparison 2026

> Note: Competitor pricing and feature claims change frequently. Before using this document for external pitching, re-verify current pricing directly on each vendor's site.

Continue to `05-Product-Requirements.md`.
