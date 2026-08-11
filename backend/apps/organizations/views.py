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
        
        from django.db.models import Count, Q
        from django.db.models.functions import TruncDate
        from datetime import timedelta
        from django.utils import timezone
        
        # Calculate stats
        total_members = org.members.count()
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
            'total_members': total_members,
            'total_elections': total_elections,
            'active_elections': active_elections,
            'total_votes_cast': total_votes_cast,
            'turnout_percentage': turnout_percentage,
            'voting_progress': voting_progress,
            'results_overview': results_overview
        }
        serializer = OrganizationStatsSerializer(data)
        return Response(serializer.data)
