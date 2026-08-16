# EMS — Open Issues

## 1. Observer Role — Permission Overreach
- **Issue:** Observer can file a voter claim (dabi) directly.
- **Issue:** Observer can also file a claim on behalf of a candidate.
- **Question:** Is this intended access, or should the Observer role be restricted from claim-filing entirely? Needs a decision on scope before fixing.

## 2. Voter Claim Approval Flow
- **Issue:** Unclear what exactly happens when a voter claim is approved — need to confirm/define whether approval should auto-add the voter to the voter list.
- **Observed:** A claim filed by an Observer, once approved, results in the voter being added to the voter list. This permission chain (Observer → claim → approval → voter list) needs to be traced and verified as correct/intended.

## 3. Dio Exception — Wrong Format on Expired Claim Window
- **Issue:** When attempting to file a claim after the claim deadline (date) has passed, the Dio exception returned is in the wrong/raw format instead of a proper, user-readable error message.
- **Fix direction:** Handle this via `DioException.type` check / interceptor and surface a clean error message instead of the raw exception.

## 4. Auditor Role — Missing Dedicated UI
- **Status:** ✅ **RESOLVED**
- **Definition & Distinction**:
  - **Observer (पर्यवेक्षक)**: Real-time election process monitoring, voter turnout observation, and transparency tracking.
  - **Auditor (लेखापरीक्षक)**: Cryptographic integrity, forensic audit trail inspection, ballot hash chain recomputation, voter receipt verification, and compliance package export.
- **Backend Implementation**: Added `/v1/elections/<id>/audit/logs/` endpoint alongside existing `/audit/verify-hash/`, `/audit/receipt/<hash>/`, and `/audit/export/`.
- **Frontend Implementation**: Built the dedicated 4-tab **Auditor Verification Portal** (`AuditPortalScreen`) with Live Hash Verification, Receipt Validator, Forensic Audit Logs Stream, and Compliance Export. Added quick launch buttons across `election_detail_screen.dart`.

## 5. Withdrawn Candidates — Dedicated List & Notification
- **Status:** ✅ **RESOLVED**
- **Backend Fix:** Added `withdraw` action on `CandidateViewSet` and `notify_candidate_withdrawn` in `NotificationService`, sending an official confirmation email upon withdrawal.
- **Frontend Fix:** Separated active candidates from withdrawn candidates into a dedicated `Withdrawn Candidates (उम्मेदवारी फिर्ता)` section with clear visual badges.

## 6. Final Candidate Publication — Mail/UI Mismatch & Scrutiny Emails
- **Status:** ✅ **RESOLVED**
- **Email Fix:** Added `notify_candidacy_claim_published(election)` triggered when nominations close (`NOMINATION_CLOSED`), broadcasting `⚖️ Candidate List Published (Claims Open)` to all members.
- **UI Synchronization:** Gated candidate lists with `isCertifiedFinal` (`candidacy_final_date` or active voting), dynamically showing `🏅 Certified Final (अन्तिम नामावली)` badges with approved candidates only, vs `📋 Preliminary Scrutiny (दाबी-विरोध जारी)` during the scrutiny window.

---

### Priority Suggestions (for discussion)
| # | Issue | Suggested Priority |
|---|-------|---------------------|
| 1 | Observer permission overreach | High (security/data integrity) |
| 2 | Voter claim approval flow unclear | High (blocks correctness of #1) |
| 3 | Dio exception wrong format | Medium (UX bug) |
| 4 | Auditor missing dedicated UI | Medium |
| 5 | Withdrawn candidates list/mail missing | High (functional gap) |
| 6 | Final candidate publication UI mismatch | High (data consistency) |