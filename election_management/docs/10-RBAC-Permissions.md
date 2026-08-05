# 10. RBAC — Role & Permission Matrix

## 10.1 Role Hierarchy

```
Super Admin (platform-wide)
   │
   └── Organization Admin (org-wide)
            │
            ├── Election Officer (per-election delegation)
            ├── Auditor (org-wide or per-election, read-only + audit access)
            ├── Observer (org-wide or per-election, read-only)
            ├── Candidate (self-scoped, is also a Voter)
            └── Voter (self-scoped)
```

Election Officer, Auditor, and Observer are **assignable per-election** (via `election_role_assignments`, see `08-Database-Design.md`) — a user's org-wide role does not automatically grant these; they must be explicitly delegated by an Org Admin per election.

## 10.2 Full Permission Matrix

| Action | Super Admin | Org Admin | Election Officer* | Candidate | Voter | Observer | Auditor |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Create organization | ✅ | — | — | — | — | — | — |
| Suspend organization | ✅ | — | — | — | — | — | — |
| View all organizations | ✅ | — | — | — | — | — | — |
| Edit org profile/branding | — | ✅ | — | — | — | — | — |
| Manage subscription/billing | — | ✅ | — | — | — | — | — |
| Import/manage members | — | ✅ | — | — | — | — | — |
| Create election | — | ✅ | — | — | — | — | — |
| Assign Election Officer/Auditor/Observer | — | ✅ | — | — | — | — | — |
| Publish election | — | ✅ | ✅** | — | — | — | — |
| Review/approve/reject nominations | — | ✅ | ✅ | — | — | — | — |
| Submit own nomination | — | — | — | ✅ | — | — | — |
| Edit own manifesto/profile (pre-silent-period) | — | — | — | ✅ | — | — | — |
| Cast vote | — | — | — | ✅*** | ✅ | — | — |
| View own vote receipt | — | — | — | ✅ | ✅ | — | — |
| View live turnout % | — | ✅ | ✅ | — | — | ✅ | ✅ |
| View individual vote content | ❌ | ❌ | ❌ | ❌ | own only (via receipt, not content) | ❌ | ❌ |
| Trigger manual recount | — | ✅ | ✅ | — | — | — | ✅ (request only, Officer executes) |
| Publish/finalize results | — | ✅ | ✅** | — | — | — | — |
| View audit log | — | ✅ (own org) | ✅ (own election) | — | — | — | ✅ |
| Export reports | — | ✅ | ✅ (own election) | — | — | ✅ (read-only) | ✅ |
| Emergency override (post-hoc state correction) | ✅ (fully logged) | — | — | — | — | — | — |

\* Only when explicitly assigned to that specific election.
\*\* If the Org Admin's org-level settings permit Election Officer self-service publishing; otherwise requires Org Admin co-sign.
\*\*\* Candidates vote as ordinary members unless the org's rules exclude candidates from voting for their own position (configurable per org).

## 10.3 Enforcement Layers (defense in depth)

1. **Database**: non-nullable `organization_id` FK on every tenant-scoped model; append-only grants on `audit_logs` and `votes`.
2. **ORM manager**: `TenantScopedManager` auto-filters querysets to the requesting context's organization.
3. **DRF permission classes**: explicit per-viewset checks (`IsOrgAdmin`, `IsElectionOfficerForElection`, etc.) — never relies solely on the manager-level filter.
4. **Serializer field-level guards**: e.g., a `VoteSerializer` never includes a `voter` field in its schema at all — not just hidden by permission, structurally absent.
5. **UI**: role-aware navigation/screens in the Flutter apps — a UX convenience layer only, never the actual security boundary.

## 10.4 Django `permission_classes` Pattern (illustrative)

```python
class IsElectionOfficerForElection(BasePermission):
    """Grants access only if the user has an election_role_assignments
    row with role='election_officer' for the specific election in the URL,
    OR is an Org Admin of that election's organization."""

    def has_object_permission(self, request, view, obj: Election):
        user = request.user
        if user.role == "org_admin" and user.organization_id == obj.organization_id:
            return True
        return ElectionRoleAssignment.objects.filter(
            user=user, election=obj, role="election_officer"
        ).exists()
```

This mirrors the `IsOrgAdmin` scoped-permission-class pattern already used for remote-work-permission views in prior cooperative-management work — same shape, applied here to election-scoped delegation instead of attendance scope.

Continue to `11-Organization-Management.md` (next batch).
