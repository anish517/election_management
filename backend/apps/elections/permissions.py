"""
Election-Specific Permissions
(doc: 10-RBAC-Permissions.md)
"""
from rest_framework import permissions
from apps.elections.models import Election, ElectionRoleAssignment

class IsElectionOfficer(permissions.BasePermission):
    """
    Allows access if the user is assigned the 'election_officer' role
    for the specific election in question.
    """
    def has_permission(self, request, view):
        return request.user.is_authenticated

    def has_object_permission(self, request, view, obj):
        # obj is expected to be an Election, or have an `election` attribute
        election = obj if isinstance(obj, Election) else getattr(obj, 'election', None)
        
        if not election:
            return False
            
        # Org Admins implicitly have all Election Officer privileges
        if request.user.is_org_admin and election.organization_id == request.user.organization_id:
            return True
            
        return ElectionRoleAssignment.objects.filter(
            user=request.user,
            election=election,
            role='election_officer'
        ).exists()


class IsObserver(permissions.BasePermission):
    """
    Allows read-only access to election dashboard and provisional results
    if user is an 'observer' for this election.
    """
    def has_permission(self, request, view):
        return request.user.is_authenticated

    def has_object_permission(self, request, view, obj):
        if request.method not in permissions.SAFE_METHODS:
            return False
            
        election = obj if isinstance(obj, Election) else getattr(obj, 'election', None)
        
        if not election:
            return False
            
        # Any authenticated user can view elections within their own organization
        # (Read-only access is safe for all organization members)
        if request.user.organization_id == election.organization_id:
            return True
            
        return False

