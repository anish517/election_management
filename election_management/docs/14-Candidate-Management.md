# 14. Candidate Management

## 14.1 Purpose

Covers the candidate experience from nomination submission through ballot appearance.

## 14.2 Nomination Submission

Candidate (an eligible Member) submits, within the nomination window:

- **Biography** (free text, character-limited, bilingual fields)
- **Manifesto** (free text or structured Q&A, org-configurable format)
- **Photo** (validated aspect ratio/size for ballot display)
- **Symbol** (optional — some org types, especially cooperatives and unions, use ballot symbols alongside photos)
- **Supporting documents** (e.g., proposer/seconder confirmation, eligibility proof) — uploaded as PDF/image, stored per `09-Authentication-Security.md` §9.4
- **Position selection** — limited to positions they meet the `eligibility_rule` for

## 14.3 Approval Workflow

```
Pending ──Election Officer verifies documents──▶ Verified ──▶ Approved ──▶ (appears on ballot)
   │                                                  │
   └──────────────────rejected, with required reason──┘──▶ Rejected ──▶ (notified; may resubmit if window open & org allows)
```

- `Verified` is a distinct step from `Approved` for organizations whose process requires a documents-check stage separate from a final committee vote/decision on approval — organizations that don't need this distinction can configure `Verified → Approved` to auto-advance.
- Rejection **requires** a reason (FR-4.2 in `05-Product-Requirements.md`) — stored, visible to the candidate, included in the audit log.

## 14.4 Appeals

- A rejected candidate may formally appeal within a configurable window (default: until nomination-close). Appeal routes to Org Admin (escalation above the Election Officer who rejected), keeping first-review and appeal-review separated.

## 14.5 Withdrawal

- Approved or pending candidates may self-withdraw up to the `withdrawal_deadline`. After that point, withdrawal requires Election Officer action (e.g., candidate becomes ineligible for external reasons) and is logged as an administrative action, not self-service.

## 14.6 Campaign & Silent Period

- Candidate profile/manifesto is editable up to `campaign_silent_from`; the field becomes read-only in both the API and UI at that timestamp (enforced server-side, not just hidden in the UI).
- If the platform's in-app candidate messaging feature (v1.1+) is enabled, it also locks at the silent-period start.

## 14.7 Ballot Ordering

- Configurable per election: alphabetical, random (freshly randomized per printed/rendered ballot instance to avoid position bias), or manually ordered by the Election Officer (logged, since manual ordering is more susceptible to fairness disputes).

## 14.8 Candidate-Facing Status Visibility

Candidates see their own nomination status in real time (`Pending` → `Verified` → `Approved`/`Rejected`) via the Flutter candidate portal — addresses the "why is my status still pending" support burden seen in manual processes.

Continue to `15-Voting-Engine.md`.
