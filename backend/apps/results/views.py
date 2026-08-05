from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from apps.elections.models import Election
from apps.results.services import TallyService

class ElectionResultsViewSet(viewsets.ViewSet):
    """
    Handles fetching live or final tally results.
    """
    permission_classes = [IsAuthenticated]

    @action(detail=False, methods=['get'])
    def results(self, request, election_pk=None):
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=404)
            
        # Security/Visibility Check
        # In a real app, we check if election.state is 'results_provisional' or 'results_final'
        # Or if 'live_turnout_enabled' allows early peek.
        if election.state not in ['voting_closed', 'results_provisional', 'results_final'] and not election.live_turnout_enabled:
            # Let org admins bypass this rule for testing
            if not request.user.is_org_admin:
                return Response({'error': 'Results are not available yet.'}, status=403)
            
        tally_data = TallyService.tally_election(election)
        return Response(tally_data)
