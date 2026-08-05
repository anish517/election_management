# 28. Roadmap

## 28.1 MVP (v1.0) — "Run One Real Election"

Goal: a real organization can run a complete, trustworthy election end-to-end.

- Org onboarding, member import
- Election creation, FPTP + Multiple Choice voting
- Nomination workflow with approval
- Secret ballot voting with OTP auth
- Automatic tally, PDF result certificate
- Full audit log
- Email + SMS notifications
- BS calendar throughout
- Khalti/eSewa billing

*(Full detail: `05-Product-Requirements.md` §5.2)*

## 28.2 v1.1 — "Flexible Voting & Trust Depth"

- Ranked-choice (STV), Approval, Weighted, Proxy, Yes/No voting methods (already designed in `15-Voting-Engine.md`, shipped here)
- Public results portal (unauthenticated view for orgs that opt into full transparency)
- WhatsApp notifications
- Webhooks/outbound API integrations
- Election templates & cloning refinements
- Write-in candidate support (opt-in per election)

## 28.3 v1.2 — "AI-Assisted Operations"

- Anomaly/fraud risk scoring (`24-AI-Features.md` §24.1)
- AI-assisted plain-language reporting (§24.2)
- AI candidate manifesto assistant (§24.3)

## 28.4 v2.0 — "Enterprise & Verifiability"

- White-label custom domains
- Multi-branch/parent-child organization hierarchy (a national association with independently-electing district chapters under one billing entity)
- **Cryptographic end-to-end verifiability** (Helios-style: voter can verify their encrypted ballot is included in the tally via public bulletin-board cryptography, without any party — including the platform — ever seeing plaintext choices). Positioned as an opt-in, higher-trust mode for organizations with the technical sophistication and stakes to want it, not a replacement for the simpler anonymization model that serves most organizations well (§9.5).
- Selfie/document-based identity verification (optional, high-assurance elections)
- SSO/SAML for enterprise organizations with existing identity providers

## 28.5 Explicitly Deferred Indefinitely (Not Roadmapped)

- Legally-binding national/government election certification — a fundamentally different regulatory and cryptographic-assurance product, not a natural extension of this platform (`01-Introduction.md` §1.7).
- Blockchain-backed vote storage — evaluated and deliberately not prioritized; the anonymization + audit-log model (§9.5, §19) delivers the practical trust guarantees organizations need without the operational complexity, cost, and immutability trade-offs (e.g., inability to correct a confirmed bug) that a blockchain-backed ledger would introduce. Revisit only if a specific enterprise customer's requirements genuinely demand it.

## 28.6 Sequencing Rationale

Voting-method flexibility (v1.1) is prioritized over AI features (v1.2) because it's a **blocking requirement** for several target segments (e.g., cooperatives commonly need weighted voting by shareholding) — without it, those organizations simply can't use the platform at all. AI features are additive value for organizations that can already fully operate on v1.0/v1.1.

Continue to `29-Appendices-Glossary.md`.
