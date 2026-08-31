"""
Tests for Phase 2: Method 1 (Online/Remote Voting) & Admin Verification Dashboard
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


class TestElectionMethodsPhase2(TestCase):
    def setUp(self):
        self.client = APIClient()

        # 1. Organization
        self.org = Organization.objects.create(
            name='Nepal Medical Council',
            slug='nmc-org',
            org_type='council',
            status=OrgStatus.ACTIVE,
        )

        # 2. Admin User
        self.admin = User.objects.create_user(
            email='admin@nmc.org.np',
            password='AdminPassword@123',
            role=UserRole.ORG_ADMIN,
            organization=self.org,
        )

        # 3. Active Election (Method 1: Hybrid)
        self.election = Election.objects.create(
            organization=self.org,
            title='NMC Central Council Election 2083',
            state='voting_open',
            election_method=ElectionMethod.ONLINE,
            online_type=OnlineVotingType.HYBRID,
            is_secret_ballot=True,
            allow_boycott=True,
        )

        # 4. Position & Candidates
        self.position = Position.objects.create(
            election=self.election,
            title='President',
            seats_available=1,
            voting_method=VotingMethod.FPTP,
        )
        self.cand1 = Candidate.objects.create(
            election=self.election,
            position=self.position,
            first_name='Dr. Sita',
            last_name='Sharma',
            email='sita@example.com',
            status=NominationStatus.APPROVED,
        )
        self.cand2 = Candidate.objects.create(
            election=self.election,
            position=self.position,
            first_name='Dr. Hari',
            last_name='Thapa',
            email='hari@example.com',
            status=NominationStatus.APPROVED,
        )

        # 5. Voter Roll entries
        self.voter1 = VoterRoll.objects.create(
            election=self.election,
            voter_id='NMC-001',
            first_name='Anil',
            last_name='Karki',
            email='anil@example.com',
            phone='9851000001',
            is_eligible=True,
        )
        self.voter2 = VoterRoll.objects.create(
            election=self.election,
            voter_id='NMC-002',
            first_name='Bikash',
            last_name='Shrestha',
            email='bikash@example.com',
            phone='9851000002',
            is_eligible=True,
        )

    def test_01_request_web_otp_success(self):
        """Voter requests email OTP on web portal."""
        resp = self.client.post('/v1/voting/request-web-otp/', {
            'election_id': str(self.election.id),
            'identifier': 'anil@example.com',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['otp_sent'])
        self.assertIn('masked_email', resp.data)

        # Verify OTP record in DB
        otp_rec = OTPRecord.objects.filter(identifier='anil@example.com', purpose='web_vote').first()
        self.assertIsNotNone(otp_rec)
        self.assertFalse(otp_rec.is_used)

    def test_02_request_web_otp_fails_if_voting_not_open(self):
        """Web OTP request is rejected if election voting is closed."""
        self.election.state = 'draft'
        self.election.save()

        resp = self.client.post('/v1/voting/request-web-otp/', {
            'election_id': str(self.election.id),
            'identifier': 'anil@example.com',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('not currently active', resp.data['error'])

    def test_03_verify_web_otp_and_generate_single_use_link(self):
        """Voter verifies email OTP on web -> generates direct_ballot_token and marks web_email verified."""
        # Create OTP record
        otp = '123456'
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()
        OTPRecord.objects.create(
            identifier='anil@example.com',
            purpose='web_vote',
            otp_hash=otp_hash,
            expires_at=timezone.now() + timezone.timedelta(minutes=10),
        )

        resp = self.client.post('/v1/voting/verify-web-otp/', {
            'election_id': str(self.election.id),
            'identifier': 'anil@example.com',
            'otp': '123456',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['verified'])
        self.assertIn('direct_token', resp.data)

        # Verify VoterRoll updated
        self.voter1.refresh_from_db()
        self.assertEqual(self.voter1.verification_channel, 'web_email')
        self.assertIsNotNone(self.voter1.verified_at)
        self.assertEqual(self.voter1.direct_ballot_token, resp.data['direct_token'])
        self.assertFalse(self.voter1.direct_ballot_token_used)

    def test_04_direct_ballot_view_fetches_ballot_without_login(self):
        """Unauthenticated voter opens direct ballot link and views ballot paper."""
        self.voter1.direct_ballot_token = 'secret-token-xyz-123'
        self.voter1.direct_ballot_token_expires_at = timezone.now() + timezone.timedelta(hours=24)
        self.voter1.save()

        # Call direct-ballot without Authorization header
        resp = self.client.get(f'/v1/voting/direct-ballot/{self.voter1.direct_ballot_token}/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['election_id'], str(self.election.id))
        self.assertEqual(resp.data['voter_name'], 'Anil Karki')
        self.assertEqual(len(resp.data['ballot']), 1)
        self.assertEqual(len(resp.data['ballot'][0]['candidates']), 2)

    def test_05_direct_vote_cast_burns_token_and_records_vote(self):
        """Voter casts ballot via direct link -> burns token, records anonymous vote."""
        self.voter1.direct_ballot_token = 'single-use-token-abc-789'
        self.voter1.direct_ballot_token_expires_at = timezone.now() + timezone.timedelta(hours=24)
        self.voter1.save()

        vote_payload = {
            'votes': [
                {
                    'position_id': str(self.position.id),
                    'candidate_id': str(self.cand1.id),
                }
            ]
        }

        resp = self.client.post(
            f'/v1/voting/direct-cast/{self.voter1.direct_ballot_token}/',
            data=vote_payload,
            format='json',
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('receipt_hash', resp.data)

        # Verify VoterRoll marked as voted & token burned
        self.voter1.refresh_from_db()
        self.assertTrue(self.voter1.has_voted)
        self.assertTrue(self.voter1.direct_ballot_token_used)

        # Verify Vote record saved
        self.assertEqual(Vote.objects.filter(election=self.election).count(), 1)

    def test_06_direct_ballot_reuse_is_rejected(self):
        """Reusing burned direct ballot token is rejected with 410 Gone."""
        self.voter1.direct_ballot_token = 'burned-token-999'
        self.voter1.direct_ballot_token_used = True
        self.voter1.has_voted = True
        self.voter1.save()

        resp = self.client.get(f'/v1/voting/direct-ballot/{self.voter1.direct_ballot_token}/')
        self.assertEqual(resp.status_code, status.HTTP_410_GONE)

        resp2 = self.client.post(
            f'/v1/voting/direct-cast/{self.voter1.direct_ballot_token}/',
            data={'votes': []},
            format='json',
        )
        self.assertEqual(resp2.status_code, status.HTTP_410_GONE)

    def test_07_in_app_session_tracks_mobile_app_channel(self):
        """In-app authenticated voter session automatically sets verification_channel to mobile_app."""
        voter_user = User.objects.create_user(
            email='bikash@example.com',
            password='Password@123',
            role=UserRole.VOTER,
            organization=self.org,
        )
        self.client.force_authenticate(user=voter_user)

        resp = self.client.post(f'/v1/elections/{self.election.id}/voting/session/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('session_token', resp.data)

        self.voter2.refresh_from_db()
        self.assertEqual(self.voter2.verification_channel, 'mobile_app')
        self.assertIsNotNone(self.voter2.verified_at)

    def test_08_verification_stats_breakdown_endpoint(self):
        """Admin endpoint returns real-time graphical breakdown metrics (Mobile App vs Web vs Pending)."""
        self.voter1.verification_channel = 'web_email'
        self.voter1.save()
        self.voter2.verification_channel = 'mobile_app'
        self.voter2.save()

        # Add an unverified voter
        VoterRoll.objects.create(
            election=self.election,
            voter_id='NMC-003',
            first_name='Chandra',
            last_name='Kandel',
            email='chandra@example.com',
            verification_channel='unverified',
        )

        self.client.force_authenticate(user=self.admin)
        resp = self.client.get(f'/v1/elections/{self.election.id}/verification-stats/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['total_voters'], 3)
        self.assertEqual(resp.data['total_verified'], 2)
        self.assertEqual(resp.data['breakdown']['mobile_app']['count'], 1)
        self.assertEqual(resp.data['breakdown']['web_email']['count'], 1)
        self.assertEqual(resp.data['breakdown']['unverified']['count'], 1)
        self.assertEqual(resp.data['verification_rate'], 66.7)
