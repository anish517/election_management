# 01. Introduction

## 1.1 Overview

Most organizations that run periodic elections — cooperatives, colleges, associations, clubs — still run them on paper ballots, spreadsheets, or ad-hoc Google Forms. This creates three recurring problems:

1. **No auditability** — disputes over vote counts have no verifiable trail.
2. **Low turnout** — physical/manual voting is inconvenient for geographically spread members.
3. **High administrative overhead** — nomination, verification, and counting are manual, slow, and error-prone.

The Election Management System (EMS) solves this by providing a **single, multi-tenant platform** any organization can onboard onto in minutes, configure for its own election rules, and run a secure, auditable, digital election.

## 1.2 Vision

To become the **default digital election infrastructure** for member-based organizations in Nepal and similar markets — the same way payment gateways became the default financial infrastructure — by being trustworthy, affordable, and easy enough for a volunteer-run housing society to operate without IT staff.

## 1.3 Mission

- Make running a fair, verifiable election as easy as creating a Google Form.
- Support every common voting method (FPTP, ranked-choice, weighted, proxy, referendum) behind one consistent interface.
- Guarantee **one member, one vote**, ballot secrecy, and a tamper-evident audit trail by default, not as a paid add-on.
- Localize fully for Nepal (Bikram Sambat calendar, NPR billing, Khalti/eSewa, Nepali-language ballots) while remaining generic enough for any country.

## 1.4 Objectives

| # | Objective | Success Metric |
|---|---|---|
| 1 | Reduce election setup time | < 30 minutes from org signup to first ballot draft |
| 2 | Increase voter turnout vs. paper elections | +20% turnout in pilot orgs |
| 3 | Eliminate manual counting errors | 0 discrepancies between system tally and audit recount |
| 4 | Support diverse org types without custom code | 10+ org types onboarded using only configuration, no code changes |
| 5 | Pass independent security review | No critical/high findings in penetration test before GA |

## 1.5 Target Organizations

| Category | Example Use Case |
|---|---|
| **Cooperatives (SACCOS)** | Board of Directors / Management Committee elections |
| **Colleges & Universities** | Student union, department representative elections |
| **Professional associations** | Engineers', doctors', lawyers' body elections |
| **Clubs & communities** | Executive committee elections |
| **Housing societies** | Society committee elections |
| **Trade unions** | Union leadership elections |
| **NGOs / INGOs** | Board member elections |
| **Corporate** | Shareholder / board elections (non-binding advisory use) |
| **Religious organizations** | Committee elections |
| **Political parties** | Internal (not national) leadership elections |

## 1.6 Guiding Principles

1. **Secrecy by default** — no admin, including Super Admin, can see who a specific voter voted for.
2. **One org, one data boundary** — no cross-tenant data leakage, enforced at the query layer, not just the UI.
3. **Everything auditable, nothing about the ballot** — every state change (candidate approved, election opened, result published) is logged; the vote content itself is never logged in plaintext against a voter identity.
4. **Configuration over code** — new org types, voting methods, and approval workflows should be configurable, not hard-coded.
5. **Works on a bad connection** — Nepal's rural connectivity means the voter app must tolerate retries, offline queuing of non-critical actions, and lightweight payloads.

## 1.7 Out of Scope (v1)

- Legally binding **national/government elections** (different legal, cryptographic, and certification requirements — e.g. Election Commission of Nepal accreditation).
- Blockchain-backed vote verification (listed as a future/premium consideration in `24-AI-Features.md` and `28-Roadmap.md`, not MVP).
- Biometric authentication (device-dependent; planned for a later phase).

## 1.8 Document Map

See `README.md` for the full file index. Continue to `02-Market-Research.md`.
