from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework import status

from django.db.models import Count, Q
from django.shortcuts import get_object_or_404

from apps.organizations.models import Organization
from apps.organizations.serializers import (
    OrganizationSerializer, OrganizationStatsSerializer,
    PlatformOrganizationSerializer, PlatformElectionSerializer,
    PlatformElectionDetailSerializer, PlatformOverviewElectionSerializer,
    PublicOrganizationSerializer, PublicElectionSerializer,
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
    from django.db.models import Case, CharField, When
    from django.db.models.functions import Cast, Lower

    # A voter is a person across the org's elections: same email counts once;
    # roll entries without an email count individually.
    voter_key = Case(
        When(~Q(elections__voter_roll__email=''), then=Lower('elections__voter_roll__email')),
        default=Cast('elections__voter_roll__id', CharField()),
    )
    return (
        Organization.objects
        .annotate(
            member_count=Count('members', filter=Q(members__deleted_at__isnull=True), distinct=True),
            election_count=Count('elections', distinct=True),
            voter_count=Count(voter_key, filter=Q(elections__voter_roll__isnull=False), distinct=True),
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
            qs = qs.filter(
                Q(name__icontains=search) | Q(slug__icontains=search)
                | Q(prefix__icontains=search) | Q(email__icontains=search)
            )
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


class PlatformOrganizationElectionsView(APIView):
    """
    GET /v1/platform/organizations/<id>/elections/ - One tenant's elections (Super Admin only)
    """
    permission_classes = [IsSuperAdmin]

    def get(self, request, org_id):
        from apps.elections.models import Election

        org = get_object_or_404(Organization, id=org_id)
        elections = (
            Election.objects.filter(organization=org)
            .annotate(
                position_count=Count('positions', distinct=True),
                voter_count=Count('voter_roll', distinct=True),
                voted_count=Count('voter_roll', filter=Q(voter_roll__has_voted=True), distinct=True),
            )
            .order_by('-created_at')
        )
        return Response(PlatformElectionSerializer(elections, many=True).data)


class PlatformElectionDetailView(APIView):
    """
    GET /v1/platform/elections/<id>/ - Read-only election overview (Super Admin only)
    """
    permission_classes = [IsSuperAdmin]

    def get(self, request, election_id):
        from django.db.models import Prefetch
        from apps.elections.models import Election, Position
        from apps.candidates.models import Candidate

        election = get_object_or_404(
            Election.objects.select_related('organization').prefetch_related(
                Prefetch(
                    'positions',
                    queryset=Position.objects.order_by('result_order', 'created_at').prefetch_related(
                        Prefetch('candidates', queryset=Candidate.objects.order_by('first_name', 'last_name'))
                    ),
                ),
            ),
            id=election_id,
        )
        data = PlatformElectionDetailSerializer(election).data
        data['organization'] = {'id': str(election.organization_id), 'name': election.organization.name}
        return Response(data)


# Elections under way: announced but without final results yet.
ACTIVE_ELECTION_STATES = [
    'published', 'nomination_open', 'nomination_closed',
    'voting_open', 'voting_closed', 'results_provisional',
]


class PlatformOverviewView(APIView):
    """
    GET /v1/platform/overview/ - Super Admin dashboard: platform totals, running
    and past elections (with their organization) and the newest organizations.
    """
    permission_classes = [IsSuperAdmin]
    LIST_LIMIT = 20

    def get(self, request):
        from apps.elections.models import Election

        elections = Election.objects.select_related('organization')
        running = elections.filter(state__in=ACTIVE_ELECTION_STATES).order_by('voting_start_at', '-created_at')
        past = elections.filter(state='results_final').order_by('-voting_end_at', '-created_at')
        return Response({
            'stats': {
                'organizations': Organization.objects.count(),
                'elections': elections.count(),
                'active_elections': running.count(),
            },
            'running_elections': PlatformOverviewElectionSerializer(running[:self.LIST_LIMIT], many=True).data,
            'past_elections': PlatformOverviewElectionSerializer(past[:self.LIST_LIMIT], many=True).data,
            'organizations': PlatformOrganizationSerializer(
                _platform_org_queryset()[:self.LIST_LIMIT], many=True
            ).data,
        })


class PublicOrganizationView(APIView):
    """
    GET /v1/public/organizations/<prefix>/
    GET /v1/public/organizations/<token>/<prefix>/
    An organization's public page & branded portal discovery.
    """
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request, prefix, token=None):
        handle = (prefix or '').strip()
        query_token = request.query_params.get('token', '').strip()
        access_token = (token or query_token).strip()

        if not handle:
            return Response(
                {'error': {'code': 'not_found', 'message': 'No organization uses this address.'}},
                status=status.HTTP_404_NOT_FOUND,
            )
        from django.db.models import Q
        org = Organization.objects.filter(
            Q(prefix__iexact=handle) | Q(slug__iexact=handle)
        ).first()

        # If not matched by prefix, check if handle or access_token is portal_token
        if not org and access_token:
            org = Organization.objects.filter(portal_token=access_token).first()
        if not org:
            org = Organization.objects.filter(portal_token=handle).first()

        if not org:
            return Response(
                {'error': {'code': 'not_found', 'message': 'No organization uses this address.'}},
                status=status.HTTP_404_NOT_FOUND,
            )

        # If access token was specified, verify it matches the organization's portal_token
        if access_token and org.portal_token and org.portal_token != access_token:
            return Response(
                {'error': {'code': 'invalid_token', 'message': 'Invalid portal access token.'}},
                status=status.HTTP_403_FORBIDDEN,
            )

        elections = org.elections.exclude(state='draft').order_by('-voting_start_at', '-created_at')
        data = PublicOrganizationSerializer(org).data
        data['elections'] = PublicElectionSerializer(elections, many=True).data
        return Response(data)
