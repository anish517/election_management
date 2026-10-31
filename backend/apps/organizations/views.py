from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status

from django.db.models import Count, Q
from django.shortcuts import get_object_or_404

from apps.organizations.models import Organization
from apps.organizations.serializers import (
    OrganizationSerializer, OrganizationStatsSerializer, PlatformOrganizationSerializer,
)
from apps.core.permissions import IsOrgAdmin, IsSuperAdmin
from apps.audit.models import log_action

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
        
        from django.db.models import Count, Q
        from django.db.models.functions import TruncDate
        from datetime import timedelta
        from django.utils import timezone
        
        # Calculate stats
        total_elections = org.elections.count()
        active_elections = org.elections.filter(state__in=['nomination_open', 'voting_open']).count()
        
        # Real data queries
        total_eligible = org.elections.aggregate(
            total=Count('voter_roll', filter=Q(voter_roll__is_eligible=True))
        )['total'] or 0
        
        total_votes_cast = org.elections.aggregate(
            total=Count('voter_roll', filter=Q(voter_roll__has_voted=True))
        )['total'] or 0
        
        turnout_percentage = (total_votes_cast / total_eligible * 100) if total_eligible > 0 else 0.0
        
        # Voting Progress (Last 7 days)
        today = timezone.now().date()
        seven_days_ago = today - timedelta(days=6)
        
        daily_votes = org.elections.filter(
            voter_roll__has_voted=True,
            voter_roll__voted_at__date__gte=seven_days_ago
        ).annotate(date=TruncDate('voter_roll__voted_at')) \
         .values('date') \
         .annotate(count=Count('voter_roll')) \
         .order_by('date')
         
        vote_dict = {item['date']: item['count'] for item in daily_votes if item['date']}
        
        voting_progress = []
        for i in range(7):
            d = seven_days_ago + timedelta(days=i)
            # Use 'M', 'T', 'W', etc.
            day_label = d.strftime('%a')[0] 
            voting_progress.append({
                'label': day_label,
                'value': vote_dict.get(d, 0)
            })
            
        # Results Overview -> Turnout by Active/Recent Elections
        recent_elections = org.elections.order_by('-created_at')[:3]
        results_overview = []
        for el in recent_elections:
            voted = el.voter_roll.filter(has_voted=True).count()
            eligible = el.voter_roll.filter(is_eligible=True).count()
            pending = max(0, eligible - voted)
            # We map Voted -> valueA, Pending -> valueB, so it stacks. We can leave valueC as 0.
            # Using short title for label
            label = el.title[:10] + ('...' if len(el.title) > 10 else '')
            results_overview.append({
                'label': label,
                'valueA': voted,
                'valueB': pending,
                'valueC': 0
            })
        
        data = {
            'total_members': total_eligible,
            'total_elections': total_elections,
            'active_elections': active_elections,
            'total_votes_cast': total_votes_cast,
            'turnout_percentage': turnout_percentage,
            'voting_progress': voting_progress,
            'results_overview': results_overview
        }
        serializer = OrganizationStatsSerializer(data)
        return Response(serializer.data)


def _platform_org_queryset():
    return (
        Organization.objects
        .annotate(
            member_count=Count('members', filter=Q(members__deleted_at__isnull=True), distinct=True),
            election_count=Count('elections', distinct=True),
        )
        .prefetch_related('users')
        .order_by('-created_at')
    )


class PlatformOrganizationListView(APIView):
    """
    GET /v1/platform/organizations/?search=&status= - All tenants (Super Admin only)
    """
    permission_classes = [IsSuperAdmin]

    def get(self, request):
        qs = _platform_org_queryset()
        search = request.query_params.get('search', '').strip()
        if search:
            qs = qs.filter(Q(name__icontains=search) | Q(slug__icontains=search) | Q(email__icontains=search))
        org_status = request.query_params.get('status', '').strip()
        if org_status:
            qs = qs.filter(status=org_status)
        return Response(PlatformOrganizationSerializer(qs, many=True).data)


class PlatformOrganizationDetailView(APIView):
    """
    GET   /v1/platform/organizations/<id>/ - One tenant (Super Admin only)
    PATCH /v1/platform/organizations/<id>/ - Change status / trial_ends_at
    """
    permission_classes = [IsSuperAdmin]

    def get(self, request, org_id):
        org = get_object_or_404(_platform_org_queryset(), id=org_id)
        return Response(PlatformOrganizationSerializer(org).data)

    def patch(self, request, org_id):
        org = get_object_or_404(_platform_org_queryset(), id=org_id)
        before = {'status': org.status, 'trial_ends_at': str(org.trial_ends_at)}
        serializer = PlatformOrganizationSerializer(org, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        log_action(
            'org.platform_updated', organization=org, actor=request.user,
            metadata={'before': before, 'after': {k: str(v) for k, v in serializer.validated_data.items()}},
        )
        return Response(serializer.data)
