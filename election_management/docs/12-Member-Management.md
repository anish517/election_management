# 12. Member Management

## 12.1 Purpose

The member roster is the source of truth for voter/candidate eligibility across every election an organization runs.

## 12.2 Member Fields

See `08-Database-Design.md` §8.2 `members` table for the canonical schema. Key business fields: `membership_status`, `membership_expiry_date`, `department`, `region` (used in position-level eligibility rules).

## 12.3 Import Workflow

1. Org Admin downloads a CSV template (columns: `member_code, full_name, email, phone, gender, department, membership_status, membership_expiry_date`).
2. Uploads filled CSV → async `process_member_import` Celery task (see `07-System-Architecture.md` §7.7) for imports over 200 rows; synchronous for smaller ones.
3. System validates: required fields present, email/phone format, duplicate detection (within org, by email+phone combo).
4. Row-level results returned: `created`, `updated` (if `member_code` matches existing), `skipped_with_reason`.
5. Newly created members enter `Invited` status; system sends activation notification (email/SMS) with a link to set up their voter login.

## 12.4 Manual Member Management

- Org Admin/delegated staff can add, edit, suspend, or mark a member expired individually.
- Suspending a member does **not** retroactively remove them from an election's already-frozen voter roll (BR-02) — it only affects future elections.

## 12.5 Membership Status → Eligibility

| Status | Can Vote (new elections) | Can Nominate |
|---|:---:|:---:|
| Active | ✅ | ✅ (if also meets position eligibility_rule) |
| Suspended | ❌ | ❌ |
| Expired | ❌ (until renewed) | ❌ |

## 12.6 Position-Level Eligibility Rules

Stored as `jsonb` on `positions.eligibility_rule` (see `08-Database-Design.md`), evaluated at nomination-submission and voter-roll-freeze time. Examples:

```json
{ "membership_status": "active", "min_membership_months": 12 }
{ "membership_status": "active", "department": ["Engineering", "Finance"] }
{ "membership_status": "active", "region": "Kathmandu Valley", "min_membership_months": 24 }
```

This flexible-rule approach avoids hard-coding org-type-specific eligibility logic into the codebase — a college's "must be a 2nd-year+ student" rule and a cooperative's "must hold shares for 12+ months" rule are both just rule configurations, not code branches.

## 12.7 Bulk Communication

- Org Admin can message all members or a filtered segment (by department/status) directly from the member list — reuses the notification templates in `20-Notification-System.md`.

## 12.8 Duplicate & Data-Quality Handling

- Duplicate detection at import time flags (does not silently merge) likely-duplicate rows for manual review.
- Phone/email format validated against Nepal (+977) and international patterns.

Continue to `13-Election-Management.md`.
