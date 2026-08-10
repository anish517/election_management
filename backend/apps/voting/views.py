from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from apps.elections.models import Election
from apps.voting.models import VoterRoll
from apps.voting.serializers import CastVoteSerializer
from apps.voting.services import BallotService
from apps.users.views import get_client_ip
from apps.audit.models import log_action

class VotingViewSet(viewsets.ViewSet):
    """
    Handles ballot generation, session creation, and secure vote casting.
    """
    permission_classes = [IsAuthenticated]

    def _get_voter_roll(self, request, election_pk):
        election = Election.objects.get(id=election_pk, organization=request.user.organization)
        # Find the member record for this user (assumes 1:1 user->member matching by email for MVP)
        # In full system, users are mapped to members explicitly. Let's do a simple lookup.
        try:
            member = request.user.organization.members.filter(email=request.user.email).first()
            if not member:
                return None
            roll, created = VoterRoll.objects.get_or_create(election=election, member=member)
            return roll
        except Exception:
            return None

    @action(detail=False, methods=['get'])
    def ballot(self, request, election_pk=None):
        """Returns the structured ballot with approved candidates."""
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=404)
            
        ballot_data = BallotService.generate_ballot(election)
        return Response({'ballot': ballot_data})

    @action(detail=False, methods=['post'])
    def session(self, request, election_pk=None):
        """Generates a voting session token."""
        roll = self._get_voter_roll(request, election_pk)
        if not roll:
            return Response({'error': 'You are not eligible to vote in this election.'}, status=403)
            
        if roll.election.state != 'voting_open':
            return Response({'error': 'Voting is not active.'}, status=400)
            
        try:
            token = BallotService.start_session(roll)
            return Response({'session_token': token})
        except ValueError as e:
            return Response({'error': str(e)}, status=400)

    @action(detail=False, methods=['post'])
    def cast(self, request, election_pk=None):
        """Casts the ballot using the session token."""
        session_token = request.data.get('session_token')
        if not session_token:
            return Response({'error': 'session_token is required.'}, status=400)
            
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=404)
            
        serializer = CastVoteSerializer(data=request.data, context={'election': election})
        if not serializer.is_valid():
            return Response(serializer.errors, status=400)
            
        try:
            receipt = BallotService.cast_vote(
                session_token=session_token, 
                ballot_data=serializer.validated_data['ballot_data'],
                ip_address=get_client_ip(request)
            )
            
            log_action('vote.casted', request.user.organization, request.user, {
                'election_id': election_pk,
                'receipt_hash': receipt
            })
            
            return Response({'success': True, 'receipt_hash': receipt})
        except ValueError as e:
            return Response({'error': str(e)}, status=400)


class VotingHistoryView(viewsets.ViewSet):
    """
    GET /v1/voting/history/
    Returns all elections the current member has successfully voted in.
    """
    permission_classes = [IsAuthenticated]

    def list(self, request):
        member = request.user.organization.members.filter(email=request.user.email).first()
        if not member:
            return Response([])
            
        rolls = VoterRoll.objects.filter(member=member, has_voted=True).select_related('election')
        history = []
        for r in rolls:
            history.append({
                'election_id': str(r.election.id),
                'title': r.election.title,
                'voted_at': r.voted_at,
                'receipt': 'Hidden for MVP' # You can add receipt_hash if we store it on VoterRoll, but we don't.
            })
        return Response(history)
