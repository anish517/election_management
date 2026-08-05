"""
RBAC Permission Classes — Defense-in-Depth
(doc: 10-RBAC-Permissions.md §10.3 Enforcement Layers)
(doc: 09-Authentication-Security.md §9.3)

Layered enforcement:
1. IsAuthenticated (base)
2. BelongsToOrganization (tenant boundary)
3. Role-specific (IsOrgAdmin, IsElectionOfficerForElection, etc.)

IMPORTANT: Views NEVER rely solely on the TenantScopedManager filter.
These permission classes are a second, independent enforcement layer.
"""
from rest_framework.permissions import BasePermission, SAFE_METHODS
from apps.users.models import UserRole


class IsSuperAdmin(BasePermission):
    """Platform-wide Super Admin only."""
    message = 'Super Admin access required.'

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == UserRole.SUPER_ADMIN
        )


class BelongsToOrganization(BasePermission):
    """
    User must belong to an organization (tenant boundary).
    Super Admins bypass this check (they are platform-wide).
    (doc: 10-RBAC-Permissions.md §10.3)
    """
    message = 'You must belong to an organization to access this resource.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        # Super admin bypasses org requirement
        if request.user.role == UserRole.SUPER_ADMIN:
            return True
        return request.user.organization_id is not None

    def has_object_permission(self, request, view, obj):
        if request.user.role == UserRole.SUPER_ADMIN:
            return True
        # Object must belong to the same organization as the user
        obj_org_id = getattr(obj, 'organization_id', None)
        if obj_org_id is None:
            # Try to get it from a nested relationship
            obj_org_id = getattr(getattr(obj, 'organization', None), 'id', None)
        return str(obj_org_id) == str(request.user.organization_id)


class IsOrgAdmin(BasePermission):
    """
    Only Organization Admins (for their own org) or Super Admins.
    (doc: 10-RBAC-Permissions.md §10.2)
    """
    message = 'Organization Admin access required.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in [UserRole.SUPER_ADMIN, UserRole.ORG_ADMIN]

    def has_object_permission(self, request, view, obj):
        if request.user.role == UserRole.SUPER_ADMIN:
            return True
        if request.user.role != UserRole.ORG_ADMIN:
            return False
        obj_org_id = getattr(obj, 'organization_id', None)
        return str(obj_org_id) == str(request.user.organization_id)


class IsOrgAdminOrReadOnly(BasePermission):
    """Allow read to any authenticated org member; write only to Org Admin."""
    message = 'Organization Admin access required for write operations.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        if request.method in SAFE_METHODS:
            return request.user.organization_id is not None
        return request.user.role in [UserRole.SUPER_ADMIN, UserRole.ORG_ADMIN]


class IsElectionOfficerForElection(BasePermission):
    """
    Grants access if the user is:
    - An Org Admin of this election's organization, OR
    - Has an election_role_assignments row with role='election_officer' for THIS election.
    (doc: 10-RBAC-Permissions.md §10.4 illustrative example)
    """
    message = 'Election Officer access required for this specific election.'

    def has_object_permission(self, request, view, obj):
        from apps.elections.models import ElectionRoleAssignment

        user = request.user

        # Org Admin has full access to all elections in their org
        if user.role == UserRole.ORG_ADMIN and user.organization_id == obj.organization_id:
            return True

        # Super Admin always has access
        if user.role == UserRole.SUPER_ADMIN:
            return True

        # Check election-specific role assignment
        election = obj if hasattr(obj, 'state') else getattr(obj, 'election', None)
        if election is None:
            return False

        return ElectionRoleAssignment.objects.filter(
            user=user,
            election=election,
            role='election_officer',
        ).exists()


class IsVoterForElection(BasePermission):
    """
    User must be on the frozen voter roll for this election.
    (doc: 06-Software-Requirements-Specification.md UC-06)
    """
    message = 'You are not on the voter roll for this election.'

    def has_object_permission(self, request, view, obj):
        from apps.voting.models import VoterRoll

        # obj is the Election
        return VoterRoll.objects.filter(
            election=obj,
            member__user=request.user,
            has_voted=False,  # Already voted check handled separately
        ).exists()


class IsAuditorOrOrgAdmin(BasePermission):
    """Auditor or Org Admin (read-only for Auditor, full for Org Admin)."""
    message = 'Auditor or Organization Admin access required.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in [
            UserRole.SUPER_ADMIN,
            UserRole.ORG_ADMIN,
            UserRole.AUDITOR,
        ]


class CanViewResults(BasePermission):
    """
    Results visibility check based on election's results_visibility setting.
    (doc: 17-Vote-Counting-Results.md §17.6)
    """
    message = 'Results are not yet publicly available for this election.'

    def has_object_permission(self, request, view, obj):
        from apps.elections.models import ElectionState

        # Results not yet available
        if obj.state not in [ElectionState.RESULTS_PROVISIONAL, ElectionState.RESULTS_FINAL]:
            return request.user.role in [
                UserRole.SUPER_ADMIN, UserRole.ORG_ADMIN, UserRole.ELECTION_OFFICER
            ]

        visibility = getattr(obj, 'results_visibility', 'admin_only')

        if visibility == 'public':
            return True

        if not request.user.is_authenticated:
            return False

        if visibility == 'org_members':
            return (
                request.user.role == UserRole.SUPER_ADMIN
                or str(request.user.organization_id) == str(obj.organization_id)
            )

        # admin_only
        return request.user.role in [
            UserRole.SUPER_ADMIN, UserRole.ORG_ADMIN, UserRole.ELECTION_OFFICER, UserRole.AUDITOR
        ]
