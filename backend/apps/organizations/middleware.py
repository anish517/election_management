"""
Organization Context Middleware
(doc: 07-System-Architecture.md §7.3 Multi-Tenancy Model)

Adds request.organization for convenience in views.
This is a convenience layer ONLY — not a security boundary.
Security is enforced by TenantScopedManager + permission_classes.
"""
from apps.users.models import UserRole


class OrganizationContextMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Attach organization to request for convenience
        if hasattr(request, 'user') and request.user.is_authenticated:
            request.organization = request.user.organization
        else:
            request.organization = None
        return self.get_response(request)
