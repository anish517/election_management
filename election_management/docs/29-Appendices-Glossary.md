# 29. Appendices

## 29.1 Glossary

| Term | Definition |
|---|---|
| **Ballot** | The set of choices a voter submits for one or more positions in an election |
| **BS (Bikram Sambat)** | The Nepali calendar system, used as the primary date display throughout the platform |
| **Election Officer** | A user delegated authority to run a specific election on behalf of an Org Admin |
| **Exhausted ballot** | In ranked-choice voting, a ballot whose ranked candidates are all eliminated/elected before all seats are filled |
| **FPTP** | First-Past-The-Post — the candidate with the most votes wins, single-choice ballot |
| **Grievance window** | The period after voting closes during which results remain provisional and can be formally contested |
| **Nomination** | A candidate's formal submission to stand for a position |
| **Org (Organization)** | A tenant on the platform — a single cooperative, college, association, etc. with isolated data |
| **Proxy voting** | Delegating one's vote to another eligible member for a specific election |
| **RCV / STV** | Ranked Choice Voting / Single Transferable Vote — preferential ballot with iterative elimination/transfer counting |
| **Silent period** | A pre-voting window during which candidate campaigning/profile edits are restricted |
| **Tenant isolation** | The guarantee that one organization's data is never accessible to another |
| **Voter roll** | The frozen, snapshotted list of members eligible to vote in a specific election |
| **Voting weight** | A multiplier applied to a member's vote, used in weighted-voting scenarios (e.g., by shareholding) |

## 29.2 Acronyms

| Acronym | Meaning |
|---|---|
| AD | Anno Domini (Gregorian calendar) |
| BS | Bikram Sambat |
| DRF | Django REST Framework |
| EMS | Election Management System |
| FCM | Firebase Cloud Messaging |
| FPTP | First-Past-The-Post |
| JWT | JSON Web Token |
| KPI | Key Performance Indicator |
| NFR | Non-Functional Requirement |
| OTP | One-Time Password |
| OWASP | Open Web Application Security Project |
| PRD | Product Requirements Document |
| RBAC | Role-Based Access Control |
| RCV | Ranked Choice Voting |
| SRS | Software Requirements Specification |
| STV | Single Transferable Vote |
| UAT | User Acceptance Testing |

## 29.3 Compliance / Launch Checklist

- [ ] Vote anonymization design independently reviewed (`09-Authentication-Security.md` §9.5)
- [ ] Tenant isolation test sweep passing on every model/viewset (`26-Testing-Strategy.md` §26.2)
- [ ] Penetration test completed with no unresolved critical/high findings
- [ ] Backup restore drill completed successfully
- [ ] BS calendar logic validated against known edge cases (month-length, year rollover)
- [ ] Khalti and eSewa merchant integration tested end-to-end, including webhook signature verification
- [ ] Retention/purge job dry-run validated against a non-production dataset
- [ ] Legal disclaimer language (`03-Nepal-Election-Workflow.md` header) reviewed
- [ ] At least one pilot organization has completed a full election-cycle UAT (`26-Testing-Strategy.md` §26.5)

## 29.4 Risk Register (Top Items)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Disputed election result damages platform trust | Medium | High | Strong audit/verifiability tooling (`19-Audit-Compliance.md`), transparent recount procedure |
| Data breach exposing member PII | Low | High | Encryption at rest/transit, field-level encryption for sensitive PII, regular pentesting |
| Regulatory ambiguity for cooperative election legitimacy | Medium | Medium | Clear positioning as a tool, not a certifying authority; legal disclaimer |
| Low digital literacy limiting adoption in some segments | Medium | Medium | Simple UI, SMS-first for voters, symbol+photo ballots |
| SMS cost scaling faster than revenue at high voter counts | Medium | Low–Medium | Push-first with SMS fallback, digest batching (`20-Notification-System.md` §20.6) |

## 29.5 References

- `04-Competitor-Analysis.md` §4.4 for external market-research sources.
- Internal architecture and security decisions throughout this document set are original design work for this project, not sourced from external references.

---

**End of documentation set.** Return to `README.md` for the full index and delivery status.
