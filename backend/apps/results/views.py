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
            
        # Security/Visibility Check:
        # Observers, auditors, voters, and electors must NOT see candidate vote tallies
        # while voting is open. Results are accessible only after voting is closed or published,
        # unless an election officer/admin is actively managing the election.
        is_admin = (
            request.user.role in ['org_admin', 'election_officer', 'super_admin']
            or getattr(request.user, 'is_org_admin', False)
            or getattr(request.user, 'is_staff', False)
        )

        is_published = election.state in ['voting_closed', 'results_provisional', 'results_final']

        if not is_published and not is_admin:
            return Response({
                'error': 'Results are not available yet. Results will be published once voting is closed.'
            }, status=403)

            
        tally_data = TallyService.tally_election(election)

        # Candidates during active voting can view ONLY their own vote counts
        if request.user.role == 'candidate' and election.state == 'voting_open':
            from apps.candidates.models import Candidate
            my_candidates = list(Candidate.objects.filter(
                election=election,
                email__iexact=request.user.email.strip().lower()
            ))
            my_cand_ids = {str(c.id) for c in my_candidates}
            my_pos_ids = {str(c.position_id) for c in my_candidates}

            scoped_results = []
            for pos in tally_data.get('results', []):
                if str(pos.get('position_id')) in my_pos_ids:
                    pos['breakdown'] = [
                        item for item in pos.get('breakdown', [])
                        if str(item.get('candidate_id')) in my_cand_ids
                    ]
                    pos['winners'] = []
                    scoped_results.append(pos)
            tally_data['results'] = scoped_results

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
