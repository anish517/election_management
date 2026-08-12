import hashlib
import json
import secrets
from django.db import transaction
from django.utils import timezone
from datetime import timedelta
from apps.voting.models import VoterRoll, VotingSession, Vote
from apps.voting.serializers import BallotPositionSerializer

class BallotService:
    @staticmethod
    def generate_ballot(election):
        """Returns the fully structured ballot for rendering."""
        positions = election.positions.all().order_by('result_order', 'id')
        return BallotPositionSerializer(positions, many=True).data

    @staticmethod
    def start_session(voter_roll):
        """Generates a 15-minute idempotent voting session."""
        if voter_roll.has_voted:
            raise ValueError("Voter has already cast a ballot.")
            
        # Revoke any old active sessions
        VotingSession.objects.filter(voter_roll=voter_roll, is_used=False).delete()
        
        session = VotingSession.objects.create(
            voter_roll=voter_roll,
            expires_at=timezone.now() + timedelta(minutes=15)
        )
        return session.token

    @staticmethod
    def cast_vote(session_token, ballot_data, ip_address=None):
        """
        ATOMIC OPERATION.
        Validates token, marks roll as voted, and strictly decouples identity
        from the saved Vote record (creating a cryptographic receipt).
        """
        try:
            session = VotingSession.objects.select_related('voter_roll', 'voter_roll__election').get(token=session_token)
        except VotingSession.DoesNotExist:
            raise ValueError("Invalid session token.")
            
        if not session.is_valid():
            raise ValueError("Session is expired or already used.")
            
        voter_roll = session.voter_roll
        election = voter_roll.election
        
        if voter_roll.has_voted:
            raise ValueError("Voter has already cast a ballot.")

        # Cryptographic receipt generation
        # Adding a salt to prevent rainbow table attacks on the vote payload
        salt = secrets.token_hex(16)
        payload_str = json.dumps(ballot_data, sort_keys=True)
        receipt_hash = hashlib.sha256(f"{payload_str}:{salt}:{session.token}".encode()).hexdigest()

        with transaction.atomic():
            # 1. Update the Voter Roll (Identity)
            voter_roll.has_voted = True
            voter_roll.voted_at = timezone.now()
            voter_roll.voted_ip_address = ip_address
            voter_roll.save(update_fields=['has_voted', 'voted_at', 'voted_ip_address'])
            
            # 2. Invalidate the session
            session.is_used = True
            session.save(update_fields=['is_used'])
            
            # 3. Create the Anonymized Vote Record
            # NO reference to voter_roll, session, or member here!
            Vote.objects.create(
                election=election,
                ballot_data=ballot_data,
                receipt_hash=receipt_hash,
                weight=1 # Default weight, as VoterRoll does not have member relation
            )
            
        return receipt_hash
