"""
Tests for Phase 3: Method 2 (Venue / Device-Based In-Person Voting Kiosks)
(doc: Election-Methods.pdf)
"""
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
import hashlib

from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole, OTPRecord
from apps.elections.models import Election, ElectionMethod, OnlineVotingType, Position, VotingMethod
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, Vote


class TestElectionMethodsPhase3(TestCase):
    def setUp(self):
        self.client = APIClient()

        # 1. Organization
        self.org = Organization.objects.create(
            name='Nepal Engineers Association',
            slug='nea-org',
            org_type='association',
            status=OrgStatus.ACTIVE,
        )

        # 2. Admin User
        self.admin = User.objects.create_user(
            email='admin@nea.org.np',
            password='AdminPassword@123',
            role=UserRole.ORG_ADMIN,
            organization=self.org,
        )

        # 3. Active Venue Election (Method 2)
        self.venue_election = Election.objects.create(
            organization=self.org,
            title='NEA 34th National Executive Committee Election',
            state='voting_open',
            election_method=ElectionMethod.VENUE,
            venue_name='Nepal Pragya Pratishthan Hall A',
            venue_address='Kamaladi, Kathmandu',
            require_venue_otp=False,
            venue_otp_channel='none',
            is_secret_ballot=True,
            allow_boycott=True,
        )

        # 4. Position & Candidates
        self.position = Position.objects.create(
            election=self.venue_election,
            title='President',
            seats_available=1,
            voting_method=VotingMethod.FPTP,
        )
        self.cand1 = Candidate.objects.create(
            election=self.venue_election,
            position=self.position,
            first_name='Er. Rajesh',
            last_name='Shrestha',
            status=NominationStatus.APPROVED,
        )
        self.cand2 = Candidate.objects.create(
            election=self.venue_election,
            position=self.position,
            first_name='Er. Bimala',
            last_name='Khadka',
            status=NominationStatus.APPROVED,
        )

        # 5. Voter Roll
        self.voter1 = VoterRoll.objects.create(
            election=self.venue_election,
            voter_id='NEA-VOTE-101',
            first_name='Er. Anil',
            last_name='Gurung',
            email='anil@example.com',
            phone='+9779841234567',
            is_eligible=True,
            has_voted=False,
        )
        self.voter2 = VoterRoll.objects.create(
            election=self.venue_election,
            voter_id='NEA-VOTE-102',
            first_name='Er. Deepa',
            last_name='Sharma',
            email='deepa@example.com',
            phone='+9779841234568',
            is_eligible=True,
            has_voted=False,
        )
        self.ineligible_voter = VoterRoll.objects.create(
            election=self.venue_election,
            voter_id='NEA-VOTE-999',
            first_name='Ineligible',
            last_name='Member',
            email='ineligible@example.com',
            is_eligible=False,
            ineligibility_reason='Membership dues unpaid',
            has_voted=False,
        )

    def test_kiosk_unlock_direct_without_otp(self):
        """Kiosk check-in unlocks immediately when 2nd-layer OTP is disabled."""
        url = '/v1/voting/kiosk/unlock/'
        payload = {
            'election_id': str(self.venue_election.id),
            'voter_id': self.voter1.voter_id,
        }
        res = self.client.post(url, payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse(res.data['require_otp'])
        self.assertIn('session_token', res.data)
        self.assertIn('ballot', res.data)
        self.assertEqual(res.data['voter_name'], 'Er. Anil Gurung')
        self.assertEqual(res.data['venue_name'], 'Nepal Pragya Pratishthan Hall A')

        # Check that verification channel is updated
        self.voter1.refresh_from_db()
        self.assertEqual(self.voter1.verification_channel, 'venue_kiosk')
        self.assertIsNotNone(self.voter1.verified_at)

    def test_kiosk_unlock_and_verify_with_2nd_layer_otp(self):
        """Kiosk check-in with 2nd-layer verification OTP flow."""
        self.venue_election.require_venue_otp = True
        self.venue_election.venue_otp_channel = 'sms'
        self.venue_election.save()

        unlock_url = '/v1/voting/kiosk/unlock/'
        unlock_res = self.client.post(unlock_url, {
            'election_id': str(self.venue_election.id),
            'voter_id': self.voter2.voter_id,
        }, format='json')

        self.assertEqual(unlock_res.status_code, status.HTTP_200_OK)
        self.assertTrue(unlock_res.data['require_otp'])
        self.assertTrue(unlock_res.data['otp_sent'])
        self.assertIn('masked_phone', unlock_res.data)

        # Retrieve generated OTP from DB
        target_id = (self.voter2.email or self.voter2.phone).lower()
        otp_rec = OTPRecord.objects.filter(identifier=target_id, purpose='venue_vote', is_used=False).first()
        self.assertIsNotNone(otp_rec)

        # Verify OTP with an intentional correct test OTP hash
        test_otp = '654321'
        otp_rec.otp_hash = hashlib.sha256(test_otp.encode()).hexdigest()
        otp_rec.save()

        verify_url = '/v1/voting/kiosk/verify-otp/'
        verify_res = self.client.post(verify_url, {
            'election_id': str(self.venue_election.id),
            'voter_id': self.voter2.voter_id,
            'otp': test_otp,
        }, format='json')

        self.assertEqual(verify_res.status_code, status.HTTP_200_OK)
        self.assertTrue(verify_res.data['verified'])
        self.assertIn('session_token', verify_res.data)
        self.assertIn('ballot', verify_res.data)

        self.voter2.refresh_from_db()
        self.assertEqual(self.voter2.verification_channel, 'venue_kiosk')

    def test_kiosk_cast_secret_ballot(self):
        """Kiosk vote casting records ballot and produces SHA-256 receipt."""
        # 1. Unlock
        unlock_res = self.client.post('/v1/voting/kiosk/unlock/', {
            'election_id': str(self.venue_election.id),
            'voter_id': self.voter1.voter_id,
        }, format='json')
        session_token = unlock_res.data['session_token']

        # 2. Cast vote
        cast_url = '/v1/voting/kiosk/cast/'
        cast_payload = {
            'session_token': session_token,
            'election_id': str(self.venue_election.id),
            'ballot_data': {
                str(self.position.id): [str(self.cand1.id)],
            },
            'device_identifier': 'kiosk_station_hall_a_01',
        }
        cast_res = self.client.post(cast_url, cast_payload, format='json')
        self.assertEqual(cast_res.status_code, status.HTTP_200_OK)
        self.assertIn('receipt_hash', cast_res.data)
        self.assertEqual(len(cast_res.data['receipt_hash']), 64)
        self.assertEqual(cast_res.data['auto_reset_seconds'], 5)

        # 3. Verify DB state
        self.voter1.refresh_from_db()
        self.assertTrue(self.voter1.has_voted)
        self.assertIsNotNone(self.voter1.voted_at)

        # 4. Verify vote counted in Vote table
        vote = Vote.objects.filter(election=self.venue_election).first()
        self.assertIsNotNone(vote)
        self.assertIn(str(self.cand1.id), str(vote.ballot_data))

    def test_kiosk_rejects_already_voted(self):
        """A voter who has already cast a vote is blocked from checking into a kiosk."""
        self.voter1.has_voted = True
        self.voter1.voted_at = timezone.now()
        self.voter1.save()

        res = self.client.post('/v1/voting/kiosk/unlock/', {
            'election_id': str(self.venue_election.id),
            'voter_id': self.voter1.voter_id,
        }, format='json')

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already cast', res.data['error'])

    def test_kiosk_rejects_ineligible_voter(self):
        """Ineligible voters are blocked with their ineligibility reason."""
        res = self.client.post('/v1/voting/kiosk/unlock/', {
            'election_id': str(self.venue_election.id),
            'voter_id': self.ineligible_voter.voter_id,
        }, format='json')

        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('Membership dues unpaid', res.data['error'])

    def test_kiosk_rejects_when_election_not_open(self):
        """Kiosk check-in fails if election state is not voting_open."""
        self.venue_election.state = 'draft'
        self.venue_election.save()

        res = self.client.post('/v1/voting/kiosk/unlock/', {
            'election_id': str(self.venue_election.id),
            'voter_id': self.voter1.voter_id,
        }, format='json')

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Voting is not active', res.data['error'])
