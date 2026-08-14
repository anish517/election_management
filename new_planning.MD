# EMS — UI/UX & Backend Task Checklist

**Project:** Election Management System (EMS)
**Scope:** Flutter frontend + Django REST backend
**Status:** Draft — pending prioritization

---

## 1. Election Rules Module

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 1.1 | Remove "International" tab | Frontend | Medium | Tab and its route/screen removed; verify no dangling nav references or unused providers left behind |
| 1.2 | Add "separation" UI to Election Rules | Frontend | Medium | Currently missing a dedicated sub-view. Pattern: tap opens a separate settings-style screen instead of inline expansion. Needs a reference screenshot/screen name to confirm exact target pattern |

---

## 2. Account / Payment Details

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 2.1 | Merge QR code and Account details into a single field | Frontend | Medium | Single form field/section stores both; a switch/toggle lets the user pick which type (QR vs Account) is active/displayed |

---

## 3. Quota & Designation Management

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 3.1 | Fix "Add Quota → Other" clearing the field | Frontend (bug) | High | Currently selecting "Other" wipes the field instead of enabling free text input |
| 3.2 | Allow custom/self-defined value under "Other" | Frontend | High | Pairs with 3.1 — once "Other" is selected, user can type their own quota label |
| 3.3 | Add Yes/No toggle to Create Designation | Frontend | Medium | Clarify what the toggle represents (e.g., "is voting eligible" / "is committee-only") — confirm exact meaning before implementation |
| 3.4 | Move "Create Designation" inside Quota Setting section | Frontend | Medium | Consolidate — currently a separate flow, needs to live under Quota Setting |
| 3.5 | Add Delete option to Create Designation | Frontend + Backend | Medium | Needs backend DELETE endpoint + confirmation dialog on frontend; check for cascade effects if designation is already assigned to members |

---

## 4. Election Committee

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 4.1 | Add Designation field to "Add Election Committee Member" | Frontend + Backend | Medium | Form field + model/serializer update if not already present |
| 4.2 | Add "Election Manager" as a role option in Assign Role | Frontend + Backend | Medium | New role value in role enum/choices; confirm permission scope for this role (what an Election Manager can/cannot do) |

---

## 5. Proposal & Supporter

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 5.1 | Keep/retain Proposal and Supporter sections | Frontend | Low | Confirm these aren't being removed elsewhere — just flagged to preserve |
| 5.2 | Add Payment to Proposal/Supporter flow | Frontend + Backend | High | Needs payment gateway decision (Khalti/eSewa per existing stack) — confirm which flow (proposal submission fee? supporter contribution?) triggers payment |

---

## 6. Voter Management

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 6.1 | Add UI for API endpoint configuration in "Create Voter" | Frontend | Medium | Confirm intent — is this for tenant-specific voter-import API config, or a dev/admin-only settings field? |

---

## 7. Email Broadcast

| # | Task | Type | Priority | Notes / Acceptance Criteria |
|---|------|------|----------|------------------------------|
| 7.1 | Store record of successful email sends | Backend | High | New model/table (e.g., `EmailBroadcastLog`) with recipient, subject, timestamp, status |
| 7.2 | Store record of failed email sends | Backend | High | Same log model, status="failed" + error reason if available from email provider/Celery task |

---

## Open Questions Before Implementation
- [ ] 1.2 — What exact screen/pattern should "separation UI" match? (screenshot or screen name needed)
- [ ] 3.3 — What does the Yes/No toggle on Create Designation actually represent?
- [ ] 4.2 — What permissions should the "Election Manager" role have?
- [ ] 5.2 — Which flow needs payment: proposal submission, supporter contribution, or both? Khalti/eSewa?
- [ ] 6.1 — Is the API endpoint field for tenant config or admin/dev use?

---

## Suggested Order of Implementation
1. **Bug fixes first:** 3.1, 3.2 (Add Quota "Other" bug)
2. **Backend logging (low risk, high value):** 7.1, 7.2 (Email broadcast records)
3. **Structural moves:** 3.4, 3.5 (Designation under Quota Setting + delete)
4. **New fields:** 4.1, 4.2, 2.1
5. **Bigger scope items (need clarification first):** 5.2 (Payment), 6.1 (API endpoint UI), 1.2 (separation UI)
6. **Cleanup:** 1.1 (remove International tab)