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
        from apps.candidates.models import Candidate, NominationStatus
        from collections import OrderedDict

        positions = election.positions.all().order_by('result_order', 'id')
        data = BallotPositionSerializer(positions, many=True).data
        
        # Exclude vacant positions that have 0 candidates (no candidates to vote for)
        data = [p for p in data if len(p.get('candidates', [])) > 0 or p.get('id') == 'pr_ballot']

        # If show_uncontested_on_ballot is False, exclude uncontested positions from voting ballots
        if not getattr(election, 'show_uncontested_on_ballot', True):
            data = [p for p in data if not p.get('is_uncontested', False)]

        # If election is 'mixed' or 'samanupatik', synthesize the Samānupātik PR Party-List ballot
        election_type = getattr(election, 'election_type', 'fptp')
        if election_type in ['mixed', 'samanupatik']:
            all_candidates = Candidate.objects.filter(
                election=election,
                status=NominationStatus.APPROVED
            ).order_by('pr_rank', 'id')

            parties_map = OrderedDict()
            party_key_map = {}
            for c in all_candidates:
                p_name = (c.party_name or c.panel_name or 'Independent').strip()
                if not p_name:
                    continue
                lower_name = p_name.lower()
                if lower_name not in party_key_map:
                    party_key_map[lower_name] = p_name
                    parties_map[p_name] = {
                        'id': p_name,
                        'name': p_name,
                        'photo_url': '',
                        'manifesto': f'{p_name} — Proportional Party-List (समानुपातिक दलगत बन्दसूची)',
                        'quota_name': '',
                        'party_name': p_name,
                        'panel_name': c.panel_name or '',
                        'slate_name': c.slate_name or '',
                        'symbol_name': c.symbol_name or '',
                        'symbol_image': c.symbol_image or '',
                        'pr_rank': 1,
                    }
                else:
                    canonical_name = party_key_map[lower_name]
                    if not parties_map[canonical_name]['symbol_image'] and c.symbol_image:
                        parties_map[canonical_name]['symbol_image'] = c.symbol_image
                    if not parties_map[canonical_name]['symbol_name'] and c.symbol_name:
                        parties_map[canonical_name]['symbol_name'] = c.symbol_name
                    if not parties_map[canonical_name]['panel_name'] and c.panel_name:
                        parties_map[canonical_name]['panel_name'] = c.panel_name

            if parties_map:
                pr_position = {
                    'id': 'pr_ballot',
                    'title': 'Samānupātik PR Party Ballot (समानुपातिक निर्वाचन प्रणाली — दलगत मतपत्र)',
                    'seats_available': getattr(election, 'total_pr_seats', 10),
                    'voting_method': 'samanupatik',
                    'max_votes_per_voter': 1,
                    'abstain_allowed': True,
                    'none_of_the_above': True,
                    'result_order': 9999,
                    'bg_color': '#4338CA',
                    'quota_name': '',
                    'quotas': [],
                    'candidates': list(parties_map.values()),
                    'is_uncontested': False,
                }
                data.append(pr_position)
            
        return data

    @staticmethod
    def start_session(voter_roll):
        """Generates a 15-minute idempotent voting session."""
        if voter_roll.has_voted:
            raise ValueError("Voter has already cast a ballot.")
            
        # Revoke any old sessions for this voter roll
        VotingSession.objects.filter(voter_roll=voter_roll).delete()
        
        session = VotingSession.objects.create(
            voter_roll=voter_roll,
            expires_at=timezone.now() + timedelta(minutes=15)
        )
        return session.token

    @staticmethod
    def cast_vote(session_token, ballot_data, ip_address=None, mac_address=None):
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
            voter_roll.voted_mac_address = mac_address or ''
            voter_roll.save(update_fields=['has_voted', 'voted_at', 'voted_ip_address', 'voted_mac_address'])
            
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
