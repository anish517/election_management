"""
Tests for Phase 1: Election Methods (Method 1: Online / Remote vs Method 2: Venue / Device-Based)
(doc: Election-Methods.pdf)
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole
from apps.elections.models import Election, ElectionMethod, OnlineVotingType
from apps.voting.models import VoterRoll


class TestElectionMethodsPhase1(TestCase):
    def setUp(self):
        self.client = APIClient()

        # 1. Organization
        self.org = Organization.objects.create(
            name='Nepal Association of Engineers',
            slug='nae-org',
            org_type='association',
            status=OrgStatus.ACTIVE,
        )

        # 2. Admin User
        self.admin = User.objects.create_user(
            email='admin@nae.org.np',
            password='AdminPassword@123',
            role=UserRole.ORG_ADMIN,
            organization=self.org,
        )
        self.client.force_authenticate(user=self.admin)

    def test_01_default_election_method_is_online_hybrid(self):
        """Elections default to Method 1 (Online) and Type 3 (Hybrid)."""
        election = Election.objects.create(
            organization=self.org,
            title='Central Committee Election 2083',
        )
        self.assertEqual(election.election_method, ElectionMethod.ONLINE)
        self.assertEqual(election.online_type, OnlineVotingType.HYBRID)
        self.assertEqual(election.venue_name, '')
        self.assertEqual(election.venue_address, '')
        self.assertFalse(election.require_venue_otp)
        self.assertEqual(election.venue_otp_channel, 'none')

    def test_02_create_method1_type1_mobile_app_election(self):
        """Method 1 Type 1: Mobile App Based election configuration."""
        election = Election.objects.create(
            organization=self.org,
            title='Mobile App Election 2083',
            election_method=ElectionMethod.ONLINE,
            online_type=OnlineVotingType.MOBILE_APP,
        )
        self.assertEqual(election.election_method, 'online')
        self.assertEqual(election.online_type, 'mobile_app')

    def test_03_create_method1_type2_web_based_election(self):
        """Method 1 Type 2: Web Based (Email OTP + Single-use Ballot Link) election configuration."""
        election = Election.objects.create(
            organization=self.org,
            title='Web Portal Election 2083',
            election_method=ElectionMethod.ONLINE,
            online_type=OnlineVotingType.WEB_BASED,
        )
        self.assertEqual(election.election_method, 'online')
        self.assertEqual(election.online_type, 'web_based')

    def test_04_create_method2_venue_device_election(self):
        """Method 2: Venue / Device-Based Voting configuration."""
        election = Election.objects.create(
            organization=self.org,
            title='Annual General Meeting 2083',
            election_method=ElectionMethod.VENUE,
            venue_name='Birendra International Convention Centre',
            venue_address='New Baneshwor, Kathmandu',
            require_venue_otp=True,
            venue_otp_channel='sms',
        )
        self.assertEqual(election.election_method, 'venue')
        self.assertEqual(election.venue_name, 'Birendra International Convention Centre')
        self.assertEqual(election.venue_address, 'New Baneshwor, Kathmandu')
        self.assertTrue(election.require_venue_otp)
        self.assertEqual(election.venue_otp_channel, 'sms')

    def test_05_voter_roll_verification_tracking_fields(self):
        """VoterRoll contains verification channel and single-use ballot link token fields."""
        election = Election.objects.create(
            organization=self.org,
            title='Test Roll Election',
        )
        roll = VoterRoll.objects.create(
            election=election,
            voter_id='VOTER-101',
            first_name='Ramesh',
            last_name='Sharma',
            email='ramesh@example.com',
            phone='9841000000',
        )
        self.assertEqual(roll.verification_channel, 'unverified')
        self.assertIsNone(roll.verified_at)
        self.assertEqual(roll.direct_ballot_token, '')
        self.assertIsNone(roll.direct_ballot_token_expires_at)
        self.assertFalse(roll.direct_ballot_token_used)

    def test_06_api_create_election_method1_and_method2(self):
        """API: POST /v1/elections/ serializes and creates elections with method configs."""
        # Test Method 1 creation
        resp1 = self.client.post('/v1/elections/', {
            'title': 'API Online Hybrid Election',
            'election_method': 'online',
            'online_type': 'hybrid',
        })
        self.assertEqual(resp1.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp1.data['election_method'], 'online')
        self.assertEqual(resp1.data['online_type'], 'hybrid')

        # Test Method 2 creation
        resp2 = self.client.post('/v1/elections/', {
            'title': 'API Venue Kiosk Election',
            'election_method': 'venue',
            'venue_name': 'City Hall Auditorium',
            'venue_address': 'Pokhara, Kaski',
            'require_venue_otp': True,
            'venue_otp_channel': 'both',
        })
        self.assertEqual(resp2.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp2.data['election_method'], 'venue')
        self.assertEqual(resp2.data['venue_name'], 'City Hall Auditorium')
        self.assertEqual(resp2.data['venue_address'], 'Pokhara, Kaski')
        self.assertTrue(resp2.data['require_venue_otp'])
        self.assertEqual(resp2.data['venue_otp_channel'], 'both')
