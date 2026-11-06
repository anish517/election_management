import hashlib
import json
import logging
import secrets
from django.db import transaction
from django.utils import timezone
from datetime import timedelta
from apps.voting.models import VoterRoll, VotingSession, Vote
from apps.voting.serializers import BallotPositionSerializer

logger = logging.getLogger(__name__)

class BallotService:
    @staticmethod
    def generate_ballot(election):
        """Returns the fully structured ballot for rendering."""
        from apps.candidates.models import Candidate, NominationStatus
        from collections import OrderedDict

        election_type = getattr(election, 'election_type', 'fptp')

        # In Samānupātik PR, voters vote for the political party / symbol list (pr_ballot).
        # Internal database positions with voting_method='samanupatik' store candidate closed lists
        # and priority ranks, so they must NOT be rendered as direct candidate voting contests.
        if election_type == 'samanupatik':
            positions = election.positions.none()
        elif election_type == 'mixed':
            # In mixed parallel elections, only FPTP / direct constituency positions are voted on individually
            positions = election.positions.exclude(voting_method='samanupatik').order_by('result_order', 'id')
        else:
            positions = election.positions.all().order_by('result_order', 'id')

        data = BallotPositionSerializer(positions, many=True).data
        
        # Exclude vacant positions that have 0 candidates (no candidates to vote for)
        data = [p for p in data if len(p.get('candidates', [])) > 0 or p.get('id') == 'pr_ballot']

        # If show_uncontested_on_ballot is False, exclude uncontested positions from voting ballots
        if not getattr(election, 'show_uncontested_on_ballot', True):
            data = [p for p in data if not p.get('is_uncontested', False)]

        # If election is 'mixed' or 'samanupatik', synthesize the Samānupātik PR Party-List ballot
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
    def parse_device_type(user_agent: str = '', channel: str = '') -> str:
        """Parses user agent into a clean human-readable device name."""
        if channel == 'venue_kiosk':
            return 'Venue Kiosk Booth'
        if channel == 'mobile_app':
            return 'EMS Mobile App'

        ua = (user_agent or '').lower()
        if not ua:
            return 'Web Browser' if channel == 'web_email' else 'Secure Electronic Terminal'

        # Form factor / OS
        if 'ipad' in ua or 'tablet' in ua:
            dev = 'Tablet'
        elif 'iphone' in ua:
            dev = 'iPhone'
        elif 'android' in ua:
            dev = 'Android Phone' if 'mobile' in ua else 'Android Tablet'
        elif 'windows' in ua:
            dev = 'Windows PC'
        elif 'macintosh' in ua or 'mac os' in ua:
            dev = 'Mac'
        elif 'linux' in ua:
            dev = 'Linux PC'
        else:
            dev = 'Device'

        # Browser
        if 'edg/' in ua or 'edge/' in ua:
            browser = 'Edge'
        elif 'chrome/' in ua or 'crios/' in ua:
            browser = 'Chrome'
        elif 'firefox/' in ua or 'fxios/' in ua:
            browser = 'Firefox'
        elif 'safari/' in ua and 'chrome' not in ua:
            browser = 'Safari'
        elif 'opera/' in ua or 'opr/' in ua:
            browser = 'Opera'
        else:
            browser = 'Browser'

        return f"{dev} ({browser})"

    @staticmethod
    def cast_vote(
        session_token,
        ballot_data,
        ip_address=None,
        mac_address=None,
        user_agent='',
        device_type='',
        verification_channel='',
        city='',
        country='',
    ):
        """
        ATOMIC OPERATION.
        Validates token, marks roll as voted, and strictly decouples identity
        from the saved Vote record (creating a cryptographic receipt).
        Audit telemetry (device, time, location, channel) is securely anchored
        to the vote for voter tracking without violating secret ballot anonymity.
        """
        with transaction.atomic():
            # Lock the session and the voter's roll row so two submissions at
            # the same moment (double tap, retry, two tabs/devices) can't both
            # pass the checks below: the second waits, then sees has_voted.
            try:
                session = VotingSession.objects.select_for_update().get(token=session_token)
            except VotingSession.DoesNotExist:
                raise ValueError("Invalid session token.")

            if not session.is_valid():
                raise ValueError("Session is expired or already used.")

            voter_roll = VoterRoll.objects.select_for_update().select_related('election__organization').get(pk=session.voter_roll_id)
            election = voter_roll.election

            if voter_roll.has_voted:
                raise ValueError("Voter has already cast a ballot.")

            # Resolve audit telemetry
            channel = verification_channel or voter_roll.verification_channel or 'web_email'
            computed_device = device_type or BallotService.parse_device_type(user_agent, channel)
            resolved_country = country or 'Nepal'
            resolved_city = city or ''
            if channel == 'venue_kiosk' and not resolved_city and election.venue_name:
                resolved_city = election.venue_name

            # Cryptographic receipt generation
            # Adding a salt to prevent rainbow table attacks on the vote payload
            salt = secrets.token_hex(16)
            payload_str = json.dumps(ballot_data, sort_keys=True)
            receipt_hash = hashlib.sha256(f"{payload_str}:{salt}:{session.token}".encode()).hexdigest()

            # 1. Update the Voter Roll (Identity)
            voter_roll.has_voted = True
            voter_roll.voted_at = timezone.now()
            voter_roll.voted_ip_address = ip_address
            voter_roll.voted_mac_address = mac_address or ''
            if channel and voter_roll.verification_channel == 'unverified':
                voter_roll.verification_channel = channel
            voter_roll.save(update_fields=['has_voted', 'voted_at', 'voted_ip_address', 'voted_mac_address', 'verification_channel'])
            
            # 2. Invalidate the session
            session.is_used = True
            session.save(update_fields=['is_used'])
            
            # 3. Create the Anonymized Vote Record
            # NO reference to voter_roll, session, or member here!
            Vote.objects.create(
                election=election,
                ballot_data=ballot_data,
                receipt_hash=receipt_hash,
                weight=1, # Default weight, as VoterRoll does not have member relation
                ip_address=ip_address,
                device_type=computed_device,
                user_agent=user_agent or '',
                city=resolved_city,
                country=resolved_country,
                verification_channel=channel,
                mac_or_device_id=mac_address or '',
            )

            voter_email = voter_roll.email
            voter_name = voter_roll.full_name
            voted_at = voter_roll.voted_at
            
        # Post-commit: automatically dispatch confirmation receipt email if voter has email
        if voter_email:
            try:
                from apps.notifications.services import NotificationService
                loc = f"{resolved_city}, {resolved_country}".strip(", ") or "Nepal"
                NotificationService.send_vote_receipt_confirmation(
                    to_email=voter_email,
                    voter_name=voter_name,
                    election=election,
                    receipt_hash=receipt_hash,
                    voted_at=voted_at,
                    device_type=computed_device,
                    verification_channel=channel,
                    ip_address=ip_address,
                    location_str=loc,
                )
            except Exception as e:
                logger.warning(f"Failed to dispatch post-vote confirmation email: {e}")

        return receipt_hash
