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
                # Also let members who have already voted see the live results!
                member = request.user.organization.members.filter(email=request.user.email).first()
                if not member or not getattr(member, 'election_rolls', None):
                    pass # fallback below
                
                from apps.voting.models import VoterRoll
                has_voted = VoterRoll.objects.filter(election=election, member=member, has_voted=True).exists()
                if not has_voted:
                    return Response({'error': 'Results are not available yet.'}, status=403)
            
        tally_data = TallyService.tally_election(election)
        return Response(tally_data)

    @action(detail=False, methods=['get'])
    def export_csv(self, request, election_pk=None):
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            from django.http import HttpResponseNotFound
            return HttpResponseNotFound('Election not found')
            
        import csv
        from django.http import HttpResponse
        
        tally_data = TallyService.tally_election(election)
        
        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = f'attachment; filename="results_{election.id}.csv"'
        
        writer = csv.writer(response)
        writer.writerow(['Position', 'Candidate', 'Vote Count', 'Is Winner'])
        
        for pos in tally_data.get('results', []):
            for cand in pos.get('breakdown', []):
                row = [
                    pos.get('title', 'Unknown'),
                    cand.get('name', 'Unknown'),
                    cand.get('score', 0),
                    'Yes' if cand.get('candidate_id') in pos.get('winners', []) else 'No'
                ]
                writer.writerow(row)
                
        # Also write turnout summary at the bottom
        writer.writerow([])
        writer.writerow(['Total Voters', tally_data.get('total_voters', 0)])
        writer.writerow(['Ballots Cast', tally_data.get('ballots_cast', 0)])
        writer.writerow(['Turnout %', f"{tally_data.get('turnout_percentage', 0)}%"])
        
        return response
