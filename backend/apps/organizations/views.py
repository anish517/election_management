from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status

from apps.organizations.serializers import OrganizationSerializer, OrganizationStatsSerializer
from apps.core.permissions import IsOrgAdmin

class OrganizationView(APIView):
    """
    GET /v1/organization/ - View org profile (all authenticated members)
    PATCH /v1/organization/ - Update org profile (Org Admin only)
    """
    def get_permissions(self):
        if self.request.method in ['PUT', 'PATCH']:
            return [IsOrgAdmin()]
        return [IsAuthenticated()]

    def get(self, request):
        serializer = OrganizationSerializer(request.user.organization)
        return Response(serializer.data)

    def patch(self, request):
        serializer = OrganizationSerializer(
            request.user.organization, 
            data=request.data, 
            partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class OrganizationStatsView(APIView):
    """
    GET /v1/organization/stats/ - Get overview metrics
    """
    permission_classes = [IsOrgAdmin]

    def get(self, request):
        org = request.user.organization
        
        # Calculate stats
        total_members = org.members.count()
        total_elections = org.elections.count()
        active_elections = org.elections.filter(state__in=['nominations_open', 'voting_active']).count()
        
        data = {
            'total_members': total_members,
            'total_elections': total_elections,
            'active_elections': active_elections
        }
        serializer = OrganizationStatsSerializer(data)
        return Response(serializer.data)
